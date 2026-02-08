default[:spyglass][:database][:cluster] = "16/main"
default[:spyglass][:database][:postgis] = "3"
default[:spyglass][:database][:nodes_store] = :flat
default[:spyglass][:serve][:threads] = node.cpu_cores
default[:spyglass][:serve][:mode] = :live
default[:spyglass][:replication][:url] = "https://osm-planet-eu-central-1.s3.dualstack.eu-central-1.amazonaws.com/planet/replication/minute"
default[:spyglass][:replication][:enabled] = true
default[:spyglass][:replication][:tileupdate] = true
default[:spyglass][:replication][:threads] = [0.5 * node.cpu_cores, 2].max.ceil
default[:spyglass][:themepark][:version] = "15dc14b1a045efc763c210ab959d6643f9d54384"
default[:spyglass][:url_prefix] = 'http://test.osm2pgsql.org/'

default[:postgresql][:versions] |= [node[:spyglass][:database][:cluster].split("/").first]
default[:postgresql][:monitor_database] = "spyglass"
# As an absolute worst case, the server might have the serving, update, and a manual generation process going on.
# Each of these connects to two databases, then we add more connections so 20% are unused and we're
# not tripping alarms.
default[:postgresql][:settings][:defaults][:max_connections] = (node.cpu_cores * 8 + 20).to_s
default[:accounts][:users][:spyglass][:status] = :role
default[:accounts][:users][:spyglass_server][:status] = :role
