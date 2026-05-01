# Elasticsearch + Kibana deployed via official Elastic Helm charts.
# Both are registered as Teleport Apps (HTTP proxy) since Teleport doesn't have
# native Elasticsearch protocol support.
#
# NOTE: Using the official Elastic charts (not Bitnami) because Bitnami removed
# all elasticsearch/kibana images from Docker Hub.

# Elasticsearch requires a privileged sysctl init container to set vm.max_map_count,
# which is incompatible with the "baseline" PodSecurity policy. Using "privileged"
# is acceptable here since this is a demo-only namespace with no user workloads.
resource "kubernetes_namespace_v1" "elasticsearch" {
  metadata {
    name = "psh-elasticsearch"
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
    }
  }
}

# ---------------------------------------------------------------------------- #
# Elasticsearch
# ---------------------------------------------------------------------------- #

resource "helm_release" "elasticsearch" {
  name       = "elasticsearch"
  namespace  = kubernetes_namespace_v1.elasticsearch.metadata[0].name
  repository = "https://helm.elastic.co"
  chart      = "elasticsearch"
  version    = "8.5.1"

  wait    = false
  timeout = 900

  values = [yamlencode({
    # 2-replica HA cluster, one pod per AZ. Sized to match the 2-node / 2-AZ
    # cluster topology — adding a 3rd ES pod on this topology forces two pods
    # onto one node, which is a worse failure domain than 2 pods on 2 nodes
    # (loss of the doubled-up node would break ES master quorum). Bump to 3
    # when the nodegroup grows past 2 nodes. Index-level redundancy comes
    # from number_of_replicas=1 in the seed script, so losing one pod does
    # not lose data.
    replicas                = 2
    antiAffinity            = "soft"
    antiAffinityTopologyKey = "topology.kubernetes.io/zone"
    # Minimal resources for demo
    resources = {
      requests = {
        cpu    = "150m"
        memory = "1Gi"
      }
      limits = {
        memory = "2Gi"
      }
    }
    # Persistence — one EBS PV per pod, each pinned to its pod's AZ via the
    # WaitForFirstConsumer storage class.
    volumeClaimTemplate = {
      accessModes = ["ReadWriteOnce"]
      resources = {
        requests = {
          storage = "10Gi"
        }
      }
    }
    # Security — set elastic password via env
    extraEnvs = [
      {
        name  = "ELASTIC_PASSWORD"
        value = random_password.elasticsearch.result
      },
      {
        name  = "xpack.security.enabled"
        value = "true"
      },
    ]
    esConfig = {
      "elasticsearch.yml" = "xpack.security.enabled: true"
    }
    # Disable tests
    tests = {
      enabled = false
    }
  })]
}

# ---------------------------------------------------------------------------- #
# Kibana — deployed as a simple Deployment+Service instead of the official Helm
# chart, because the chart's pre-install hook (enrollment token) fails with
# self-signed TLS certs and is not easily disabled.
# ---------------------------------------------------------------------------- #

# Kibana config — anonymous auth provider skips login screen since Teleport
# handles real authentication. Env vars cannot express nested authc.providers
# config (known Kibana limitation), so we mount kibana.yml instead.
resource "kubernetes_config_map" "kibana_config" {
  metadata {
    name      = "kibana-config"
    namespace = kubernetes_namespace_v1.elasticsearch.metadata[0].name
  }
  data = {
    "kibana.yml" = <<-YAML
      server.host: "0.0.0.0"
      elasticsearch.hosts: ["https://elasticsearch-master:9200"]
      elasticsearch.username: "kibana_system"
      elasticsearch.password: "${random_password.elasticsearch.result}"
      elasticsearch.ssl.verificationMode: none
      xpack.security.authc.providers:
        anonymous.anonymous1:
          order: 0
          credentials:
            username: "anonymous_user"
            password: "anonymous_pass"
      uiSettings.overrides:
        defaultRoute: "/app/dashboards#/view/teleport-audit-dashboard"
    YAML
  }
}

resource "kubernetes_deployment_v1" "kibana" {
  metadata {
    name      = "kibana"
    namespace = kubernetes_namespace_v1.elasticsearch.metadata[0].name
    labels    = { app = "kibana" }
  }

  spec {
    replicas = 1
    selector {
      match_labels = { app = "kibana" }
    }
    template {
      metadata {
        labels = { app = "kibana" }
      }
      spec {
        # Idempotently re-create everything Kibana needs in the ES security
        # index on every pod start. The Bitnami chart only bootstraps the
        # `elastic` superuser; kibana_system's password and the anonymous
        # user/role used by Kibana's anonymous auth provider all live in
        # the ES security index, which is wiped along with the PVC any time
        # the ES cluster is rebuilt. The one-shot seed Job that originally
        # set these up is `Complete` and never re-runs. Doing it here on
        # every Kibana pod start is idempotent and self-heals after rebuilds.
        init_container {
          name    = "align-kibana-auth"
          image   = "curlimages/curl:latest"
          command = ["/bin/sh", "-c", <<-SCRIPT
            set -e
            ES_URL="https://elasticsearch-master:9200"
            until curl -ksf -u "elastic:$ELASTIC_PASSWORD" "$ES_URL/_cluster/health" >/dev/null; do
              echo "Waiting for Elasticsearch..."
              sleep 5
            done
            # 1. Align kibana_system password with kibana.yml.
            curl -ksf -u "elastic:$ELASTIC_PASSWORD" \
              -X POST "$ES_URL/_security/user/kibana_system/_password" \
              -H "Content-Type: application/json" \
              -d "{\"password\":\"$ELASTIC_PASSWORD\"}"
            echo "kibana_system password aligned"
            # 2. Re-create kibana_anonymous role (read-only browse).
            curl -ksf -u "elastic:$ELASTIC_PASSWORD" \
              -X PUT "$ES_URL/_security/role/kibana_anonymous" \
              -H "Content-Type: application/json" \
              -d '{"cluster":["monitor"],"indices":[{"names":["*"],"privileges":["read","view_index_metadata"]}],"applications":[{"application":"kibana-.kibana","privileges":["feature_discover.all","feature_dashboard.all","feature_visualize.all"],"resources":["*"]}]}'
            echo "kibana_anonymous role aligned"
            # 3. Re-create anonymous_user (matches kibana.yml anonymous provider creds).
            curl -ksf -u "elastic:$ELASTIC_PASSWORD" \
              -X POST "$ES_URL/_security/user/anonymous_user" \
              -H "Content-Type: application/json" \
              -d '{"password":"anonymous_pass","roles":["kibana_anonymous"],"full_name":"Teleport User"}'
            echo "anonymous_user aligned"
          SCRIPT
          ]
          env {
            name  = "ELASTIC_PASSWORD"
            value = random_password.elasticsearch.result
          }
        }

        container {
          name  = "kibana"
          image = "docker.elastic.co/kibana/kibana:8.5.1"

          port {
            container_port = 5601
            name           = "http"
          }

          volume_mount {
            name       = "kibana-config"
            mount_path = "/usr/share/kibana/config/kibana.yml"
            sub_path   = "kibana.yml"
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "512Mi"
            }
            limits = {
              memory = "1Gi"
            }
          }
        }

        volume {
          name = "kibana-config"
          config_map {
            name = kubernetes_config_map.kibana_config.metadata[0].name
          }
        }
      }
    }
  }

  depends_on = [helm_release.elasticsearch]
}

resource "kubernetes_service_v1" "kibana" {
  metadata {
    name      = "kibana"
    namespace = kubernetes_namespace_v1.elasticsearch.metadata[0].name
    labels    = { app = "kibana" }
  }
  spec {
    selector = { app = "kibana" }
    port {
      port        = 5601
      target_port = 5601
      name        = "http"
    }
  }
}

# ---------------------------------------------------------------------------- #
# Seed Data — same top movies dataset used by other databases
# ---------------------------------------------------------------------------- #

resource "kubernetes_config_map" "elasticsearch_seed" {
  metadata {
    name      = "elasticsearch-seed-data"
    namespace = kubernetes_namespace_v1.elasticsearch.metadata[0].name
  }
  data = {
    "seed.sh" = <<-SCRIPT
      #!/bin/sh
      set -e
      ES_URL="https://elasticsearch-master:9200"
      echo "Waiting for Elasticsearch to be ready..."
      until curl -ksf -u "elastic:$ES_PASSWORD" "$ES_URL/_cluster/health" | grep -qE '"status":"(green|yellow)"'; do
        sleep 5
      done
      echo "Setting kibana_system password..."
      curl -ksf -u "elastic:$ES_PASSWORD" -X POST "$ES_URL/_security/user/kibana_system/_password" -H "Content-Type: application/json" -d "{\"password\":\"$ES_PASSWORD\"}" || true
      echo "Creating top_movies index..."
      # number_of_replicas=1 ensures shards are duplicated to a second node so
      # losing one ES pod (or its EBS PV) does not lose data.
      curl -ksf -u "elastic:$ES_PASSWORD" -X PUT "$ES_URL/top_movies" -H "Content-Type: application/json" -d '{"settings":{"number_of_shards":1,"number_of_replicas":1},"mappings":{"properties":{"rank":{"type":"integer"},"title":{"type":"text","fields":{"keyword":{"type":"keyword"}}},"year":{"type":"integer"},"director":{"type":"text","fields":{"keyword":{"type":"keyword"}}}}}}'  || true
      echo "Loading seed data..."
      curl -ksf -u "elastic:$ES_PASSWORD" -X POST "$ES_URL/_bulk" -H "Content-Type: application/x-ndjson" --data-binary @/data/bulk.ndjson
      echo "Seed data loaded. Verifying count..."
      curl -ksf -u "elastic:$ES_PASSWORD" "$ES_URL/top_movies/_count"
      echo ""

      # Create role for anonymous Kibana access (read-only browse)
      echo "Creating kibana_anonymous role..."
      curl -ksf -u "elastic:$ES_PASSWORD" -X PUT "$ES_URL/_security/role/kibana_anonymous" \
        -H "Content-Type: application/json" \
        -d '{"cluster":["monitor"],"indices":[{"names":["*"],"privileges":["read","view_index_metadata"]}],"applications":[{"application":"kibana-.kibana","privileges":["feature_discover.all","feature_dashboard.all","feature_visualize.all"],"resources":["*"]}]}'
      echo ""

      # Create anonymous user for Kibana auto-login (Teleport handles real auth)
      echo "Creating anonymous_user for Kibana..."
      curl -ksf -u "elastic:$ES_PASSWORD" -X POST "$ES_URL/_security/user/anonymous_user" \
        -H "Content-Type: application/json" \
        -d '{"password":"anonymous_pass","roles":["kibana_anonymous"],"full_name":"Teleport User"}'
      echo ""
    SCRIPT

    "bulk.ndjson" = <<-NDJSON
      {"index":{"_index":"top_movies","_id":"1"}}
      {"rank":1,"title":"The Shawshank Redemption","year":1994,"director":"Frank Darabont"}
      {"index":{"_index":"top_movies","_id":"2"}}
      {"rank":2,"title":"The Godfather","year":1972,"director":"Francis Ford Coppola"}
      {"index":{"_index":"top_movies","_id":"3"}}
      {"rank":3,"title":"The Dark Knight","year":2008,"director":"Christopher Nolan"}
      {"index":{"_index":"top_movies","_id":"4"}}
      {"rank":4,"title":"The Godfather Part II","year":1974,"director":"Francis Ford Coppola"}
      {"index":{"_index":"top_movies","_id":"5"}}
      {"rank":5,"title":"12 Angry Men","year":1957,"director":"Sidney Lumet"}
      {"index":{"_index":"top_movies","_id":"6"}}
      {"rank":6,"title":"Schindlers List","year":1993,"director":"Steven Spielberg"}
      {"index":{"_index":"top_movies","_id":"7"}}
      {"rank":7,"title":"The Lord of the Rings: The Return of the King","year":2003,"director":"Peter Jackson"}
      {"index":{"_index":"top_movies","_id":"8"}}
      {"rank":8,"title":"Pulp Fiction","year":1994,"director":"Quentin Tarantino"}
      {"index":{"_index":"top_movies","_id":"9"}}
      {"rank":9,"title":"The Lord of the Rings: The Fellowship of the Ring","year":2001,"director":"Peter Jackson"}
      {"index":{"_index":"top_movies","_id":"10"}}
      {"rank":10,"title":"The Good, the Bad and the Ugly","year":1966,"director":"Sergio Leone"}
      {"index":{"_index":"top_movies","_id":"11"}}
      {"rank":11,"title":"Forrest Gump","year":1994,"director":"Robert Zemeckis"}
      {"index":{"_index":"top_movies","_id":"12"}}
      {"rank":12,"title":"Fight Club","year":1999,"director":"David Fincher"}
      {"index":{"_index":"top_movies","_id":"13"}}
      {"rank":13,"title":"The Lord of the Rings: The Two Towers","year":2002,"director":"Peter Jackson"}
      {"index":{"_index":"top_movies","_id":"14"}}
      {"rank":14,"title":"Inception","year":2010,"director":"Christopher Nolan"}
      {"index":{"_index":"top_movies","_id":"15"}}
      {"rank":15,"title":"Star Wars: Episode V - The Empire Strikes Back","year":1980,"director":"Irvin Kershner"}
      {"index":{"_index":"top_movies","_id":"16"}}
      {"rank":16,"title":"The Matrix","year":1999,"director":"Lana Wachowski"}
      {"index":{"_index":"top_movies","_id":"17"}}
      {"rank":17,"title":"Goodfellas","year":1990,"director":"Martin Scorsese"}
      {"index":{"_index":"top_movies","_id":"18"}}
      {"rank":18,"title":"One Flew Over the Cuckoos Nest","year":1975,"director":"Milos Forman"}
      {"index":{"_index":"top_movies","_id":"19"}}
      {"rank":19,"title":"Se7en","year":1995,"director":"David Fincher"}
      {"index":{"_index":"top_movies","_id":"20"}}
      {"rank":20,"title":"Its a Wonderful Life","year":1946,"director":"Frank Capra"}
      {"index":{"_index":"top_movies","_id":"21"}}
      {"rank":21,"title":"The Silence of the Lambs","year":1991,"director":"Jonathan Demme"}
      {"index":{"_index":"top_movies","_id":"22"}}
      {"rank":22,"title":"Saving Private Ryan","year":1998,"director":"Steven Spielberg"}
      {"index":{"_index":"top_movies","_id":"23"}}
      {"rank":23,"title":"City of God","year":2002,"director":"Fernando Meirelles"}
      {"index":{"_index":"top_movies","_id":"24"}}
      {"rank":24,"title":"Interstellar","year":2014,"director":"Christopher Nolan"}
      {"index":{"_index":"top_movies","_id":"25"}}
      {"rank":25,"title":"Life Is Beautiful","year":1997,"director":"Roberto Benigni"}
      {"index":{"_index":"top_movies","_id":"26"}}
      {"rank":26,"title":"The Green Mile","year":1999,"director":"Frank Darabont"}
      {"index":{"_index":"top_movies","_id":"27"}}
      {"rank":27,"title":"Star Wars: Episode IV - A New Hope","year":1977,"director":"George Lucas"}
      {"index":{"_index":"top_movies","_id":"28"}}
      {"rank":28,"title":"Terminator 2: Judgment Day","year":1991,"director":"James Cameron"}
      {"index":{"_index":"top_movies","_id":"29"}}
      {"rank":29,"title":"Back to the Future","year":1985,"director":"Robert Zemeckis"}
      {"index":{"_index":"top_movies","_id":"30"}}
      {"rank":30,"title":"Spirited Away","year":2001,"director":"Hayao Miyazaki"}
      {"index":{"_index":"top_movies","_id":"31"}}
      {"rank":31,"title":"The Pianist","year":2002,"director":"Roman Polanski"}
      {"index":{"_index":"top_movies","_id":"32"}}
      {"rank":32,"title":"Psycho","year":1960,"director":"Alfred Hitchcock"}
      {"index":{"_index":"top_movies","_id":"33"}}
      {"rank":33,"title":"Parasite","year":2019,"director":"Bong Joon-ho"}
      {"index":{"_index":"top_movies","_id":"34"}}
      {"rank":34,"title":"Gladiator","year":2000,"director":"Ridley Scott"}
      {"index":{"_index":"top_movies","_id":"35"}}
      {"rank":35,"title":"The Lion King","year":1994,"director":"Roger Allers"}
      {"index":{"_index":"top_movies","_id":"36"}}
      {"rank":36,"title":"Leon: The Professional","year":1994,"director":"Luc Besson"}
      {"index":{"_index":"top_movies","_id":"37"}}
      {"rank":37,"title":"American History X","year":1998,"director":"Tony Kaye"}
      {"index":{"_index":"top_movies","_id":"38"}}
      {"rank":38,"title":"The Departed","year":2006,"director":"Martin Scorsese"}
      {"index":{"_index":"top_movies","_id":"39"}}
      {"rank":39,"title":"Whiplash","year":2014,"director":"Damien Chazelle"}
      {"index":{"_index":"top_movies","_id":"40"}}
      {"rank":40,"title":"The Prestige","year":2006,"director":"Christopher Nolan"}
      {"index":{"_index":"top_movies","_id":"41"}}
      {"rank":41,"title":"The Usual Suspects","year":1995,"director":"Bryan Singer"}
      {"index":{"_index":"top_movies","_id":"42"}}
      {"rank":42,"title":"Casablanca","year":1942,"director":"Michael Curtiz"}
      {"index":{"_index":"top_movies","_id":"43"}}
      {"rank":43,"title":"Harakiri","year":1962,"director":"Masaki Kobayashi"}
      {"index":{"_index":"top_movies","_id":"44"}}
      {"rank":44,"title":"The Intouchables","year":2011,"director":"Olivier Nakache"}
      {"index":{"_index":"top_movies","_id":"45"}}
      {"rank":45,"title":"Modern Times","year":1936,"director":"Charlie Chaplin"}
      {"index":{"_index":"top_movies","_id":"46"}}
      {"rank":46,"title":"Cinema Paradiso","year":1988,"director":"Giuseppe Tornatore"}
      {"index":{"_index":"top_movies","_id":"47"}}
      {"rank":47,"title":"Once Upon a Time in the West","year":1968,"director":"Sergio Leone"}
      {"index":{"_index":"top_movies","_id":"48"}}
      {"rank":48,"title":"Rear Window","year":1954,"director":"Alfred Hitchcock"}
      {"index":{"_index":"top_movies","_id":"49"}}
      {"rank":49,"title":"Alien","year":1979,"director":"Ridley Scott"}
      {"index":{"_index":"top_movies","_id":"50"}}
      {"rank":50,"title":"City Lights","year":1931,"director":"Charlie Chaplin"}
      {"index":{"_index":"top_movies","_id":"51"}}
      {"rank":51,"title":"Apocalypse Now","year":1979,"director":"Francis Ford Coppola"}
      {"index":{"_index":"top_movies","_id":"52"}}
      {"rank":52,"title":"Memento","year":2000,"director":"Christopher Nolan"}
      {"index":{"_index":"top_movies","_id":"53"}}
      {"rank":53,"title":"Django Unchained","year":2012,"director":"Quentin Tarantino"}
      {"index":{"_index":"top_movies","_id":"54"}}
      {"rank":54,"title":"Indiana Jones and the Raiders of the Lost Ark","year":1981,"director":"Steven Spielberg"}
      {"index":{"_index":"top_movies","_id":"55"}}
      {"rank":55,"title":"WALL-E","year":2008,"director":"Andrew Stanton"}
      {"index":{"_index":"top_movies","_id":"56"}}
      {"rank":56,"title":"The Lives of Others","year":2006,"director":"Florian Henckel von Donnersmarck"}
      {"index":{"_index":"top_movies","_id":"57"}}
      {"rank":57,"title":"Sunset Boulevard","year":1950,"director":"Billy Wilder"}
      {"index":{"_index":"top_movies","_id":"58"}}
      {"rank":58,"title":"Paths of Glory","year":1957,"director":"Stanley Kubrick"}
      {"index":{"_index":"top_movies","_id":"59"}}
      {"rank":59,"title":"The Shining","year":1980,"director":"Stanley Kubrick"}
      {"index":{"_index":"top_movies","_id":"60"}}
      {"rank":60,"title":"The Great Dictator","year":1940,"director":"Charlie Chaplin"}
      {"index":{"_index":"top_movies","_id":"61"}}
      {"rank":61,"title":"Witness for the Prosecution","year":1957,"director":"Billy Wilder"}
      {"index":{"_index":"top_movies","_id":"62"}}
      {"rank":62,"title":"Aliens","year":1986,"director":"James Cameron"}
      {"index":{"_index":"top_movies","_id":"63"}}
      {"rank":63,"title":"American Beauty","year":1999,"director":"Sam Mendes"}
      {"index":{"_index":"top_movies","_id":"64"}}
      {"rank":64,"title":"The Dark Knight Rises","year":2012,"director":"Christopher Nolan"}
      {"index":{"_index":"top_movies","_id":"65"}}
      {"rank":65,"title":"Grave of the Fireflies","year":1988,"director":"Isao Takahata"}
      {"index":{"_index":"top_movies","_id":"66"}}
      {"rank":66,"title":"Oldboy","year":2003,"director":"Park Chan-wook"}
      {"index":{"_index":"top_movies","_id":"67"}}
      {"rank":67,"title":"Toy Story","year":1995,"director":"John Lasseter"}
      {"index":{"_index":"top_movies","_id":"68"}}
      {"rank":68,"title":"Das Boot","year":1981,"director":"Wolfgang Petersen"}
      {"index":{"_index":"top_movies","_id":"69"}}
      {"rank":69,"title":"Amadeus","year":1984,"director":"Milos Forman"}
      {"index":{"_index":"top_movies","_id":"70"}}
      {"rank":70,"title":"Princess Mononoke","year":1997,"director":"Hayao Miyazaki"}
      {"index":{"_index":"top_movies","_id":"71"}}
      {"rank":71,"title":"Coco","year":2017,"director":"Lee Unkrich"}
      {"index":{"_index":"top_movies","_id":"72"}}
      {"rank":72,"title":"Avengers: Endgame","year":2019,"director":"Anthony Russo"}
      {"index":{"_index":"top_movies","_id":"73"}}
      {"rank":73,"title":"The Hunt","year":2012,"director":"Thomas Vinterberg"}
      {"index":{"_index":"top_movies","_id":"74"}}
      {"rank":74,"title":"Good Will Hunting","year":1997,"director":"Gus Van Sant"}
      {"index":{"_index":"top_movies","_id":"75"}}
      {"rank":75,"title":"Requiem for a Dream","year":2000,"director":"Darren Aronofsky"}
      {"index":{"_index":"top_movies","_id":"76"}}
      {"rank":76,"title":"Toy Story 3","year":2010,"director":"Lee Unkrich"}
      {"index":{"_index":"top_movies","_id":"77"}}
      {"rank":77,"title":"3 Idiots","year":2009,"director":"Rajkumar Hirani"}
      {"index":{"_index":"top_movies","_id":"78"}}
      {"rank":78,"title":"Come and See","year":1985,"director":"Elem Klimov"}
      {"index":{"_index":"top_movies","_id":"79"}}
      {"rank":79,"title":"High and Low","year":1963,"director":"Akira Kurosawa"}
      {"index":{"_index":"top_movies","_id":"80"}}
      {"rank":80,"title":"Singin in the Rain","year":1952,"director":"Stanley Donen"}
      {"index":{"_index":"top_movies","_id":"81"}}
      {"rank":81,"title":"Capernaum","year":2018,"director":"Nadine Labaki"}
      {"index":{"_index":"top_movies","_id":"82"}}
      {"rank":82,"title":"Inglourious Basterds","year":2009,"director":"Quentin Tarantino"}
      {"index":{"_index":"top_movies","_id":"83"}}
      {"rank":83,"title":"2001: A Space Odyssey","year":1968,"director":"Stanley Kubrick"}
      {"index":{"_index":"top_movies","_id":"84"}}
      {"rank":84,"title":"Braveheart","year":1995,"director":"Mel Gibson"}
      {"index":{"_index":"top_movies","_id":"85"}}
      {"rank":85,"title":"Full Metal Jacket","year":1987,"director":"Stanley Kubrick"}
      {"index":{"_index":"top_movies","_id":"86"}}
      {"rank":86,"title":"A Beautiful Mind","year":2001,"director":"Ron Howard"}
      {"index":{"_index":"top_movies","_id":"87"}}
      {"rank":87,"title":"Snatch","year":2000,"director":"Guy Ritchie"}
      {"index":{"_index":"top_movies","_id":"88"}}
      {"rank":88,"title":"Eternal Sunshine of the Spotless Mind","year":2004,"director":"Michel Gondry"}
      {"index":{"_index":"top_movies","_id":"89"}}
      {"rank":89,"title":"Scarface","year":1983,"director":"Brian De Palma"}
      {"index":{"_index":"top_movies","_id":"90"}}
      {"rank":90,"title":"The Truman Show","year":1998,"director":"Peter Weir"}
      {"index":{"_index":"top_movies","_id":"91"}}
      {"rank":91,"title":"Heat","year":1995,"director":"Michael Mann"}
      {"index":{"_index":"top_movies","_id":"92"}}
      {"rank":92,"title":"Ikiru","year":1952,"director":"Akira Kurosawa"}
      {"index":{"_index":"top_movies","_id":"93"}}
      {"rank":93,"title":"A Clockwork Orange","year":1971,"director":"Stanley Kubrick"}
      {"index":{"_index":"top_movies","_id":"94"}}
      {"rank":94,"title":"Up","year":2009,"director":"Pete Docter"}
      {"index":{"_index":"top_movies","_id":"95"}}
      {"rank":95,"title":"Taxi Driver","year":1976,"director":"Martin Scorsese"}
      {"index":{"_index":"top_movies","_id":"96"}}
      {"rank":96,"title":"Reservoir Dogs","year":1992,"director":"Quentin Tarantino"}
      {"index":{"_index":"top_movies","_id":"97"}}
      {"rank":97,"title":"To Kill a Mockingbird","year":1962,"director":"Robert Mulligan"}
      {"index":{"_index":"top_movies","_id":"98"}}
      {"rank":98,"title":"The Sting","year":1973,"director":"George Roy Hill"}
      {"index":{"_index":"top_movies","_id":"99"}}
      {"rank":99,"title":"Lawrence of Arabia","year":1962,"director":"David Lean"}
      {"index":{"_index":"top_movies","_id":"100"}}
      {"rank":100,"title":"Vertigo","year":1958,"director":"Alfred Hitchcock"}
    NDJSON
  }
}

resource "kubernetes_job" "elasticsearch_seed" {
  metadata {
    name      = "elasticsearch-seed"
    namespace = kubernetes_namespace_v1.elasticsearch.metadata[0].name
  }

  spec {
    backoff_limit = 3

    template {
      metadata {}
      spec {
        restart_policy = "OnFailure"

        container {
          name    = "seed"
          image   = "curlimages/curl:latest"
          command = ["/bin/sh", "/scripts/seed.sh"]

          env {
            name  = "ES_PASSWORD"
            value = random_password.elasticsearch.result
          }

          volume_mount {
            name       = "scripts"
            mount_path = "/scripts"
          }

          volume_mount {
            name       = "data"
            mount_path = "/data"
          }
        }

        volume {
          name = "scripts"
          config_map {
            name         = kubernetes_config_map.elasticsearch_seed.metadata[0].name
            default_mode = "0755"
            items {
              key  = "seed.sh"
              path = "seed.sh"
            }
          }
        }

        volume {
          name = "data"
          config_map {
            name = kubernetes_config_map.elasticsearch_seed.metadata[0].name
            items {
              key  = "bulk.ndjson"
              path = "bulk.ndjson"
            }
          }
        }
      }
    }
  }

  wait_for_completion = false

  depends_on = [helm_release.elasticsearch]
}

# ---------------------------------------------------------------------------- #
# Teleport Role — full access to Elasticsearch API + Kibana
# ---------------------------------------------------------------------------- #

resource "kubectl_manifest" "teleport_role_elasticsearch" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v1"
    kind       = "TeleportRoleV7"
    metadata = {
      annotations = {
        "teleport.dev/keep" = "true"
      }
      finalizers = ["resources.teleport.dev/deletion"]
      generation = 1
      name       = "${var.resource_prefix}elasticsearch"
      namespace  = helm_release.teleport_cluster.namespace
    }
    spec = {
      allow = {
        app_labels = {
          app = ["elasticsearch", "kibana"]
        }
      }
    }
  })
}
