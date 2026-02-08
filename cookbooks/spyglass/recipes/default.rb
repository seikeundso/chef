#
# Cookbook:: spyglass
# Recipe:: default
#
# Copyright:: 2025, OpenStreetMap Foundation
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

include_recipe "accounts"
include_recipe "git"
include_recipe "nginx"
include_recipe "podman"
include_recipe "postgresql"
include_recipe "python"
include_recipe "tools"

postgresql_version = node[:spyglass][:database][:cluster].split("/").first
postgis_version = node[:spyglass][:database][:postgis]

db_passwords = data_bag_item("db", "passwords")

package %w[
  osm2pgsql
  gdal-bin
  python3-yaml
  python3-psycopg2
  golang-1.23
]

package "postgresql-#{postgresql_version}-postgis-#{postgis_version}"

directory "/srv/spyglass.openstreetmap.org" do
  user "spyglass"
  group "spyglass"
  mode "755"
end

directory "/srv/local" do
  user "spyglass"
  group "spyglass"
  mode "755"
end

git "/srv/spyglass.openstreetmap.org" do
  action :sync
  repository "https://codeberg.org/jot/osm-spyglass.git"
  depth 1
  user "spyglass"
  group "spyglass"
end

template "/srv/local/config.js" do
  source "config.erb"
  owner  "spyglass"
  group  "spyglass"
  mode   "0644"
  variables(url_prefix: node[:spyglass][:url_prefix])
end

execute "/srv/spyglass.openstreetmap.org/server" do
  action :nothing
  command "/usr/lib/go-1.23/bin/go build -buildvcs=false"
  cwd "/srv/spyglass.openstreetmap.org/server"
  user "root"
  group "root"
  subscribes :run, "git[/srv/spyglass.openstreetmap.org]"
end

link "/usr/local/bin/spyglass" do
  to "/srv/spyglass.openstreetmap.org/server/spyglass"
end

template "/usr/local/bin/import" do
  source "import.erb"
  owner "root"
  group "root"
  mode "755"
end

template "/usr/local/bin/update" do
  source "update.erb"
  owner "root"
  group "root"
  mode "755"
end

nginx_site "default" do
  action [:delete]
end

nginx_site "spyglass.openstreetmap.org" do
  template "nginx.erb"
end

ssl_certificate node[:fqdn] do
  domains [node[:fqdn]]
  notifies :reload, "service[nginx]"
end

themepark_directory = "/srv/spyglass.openstreetmap.org/osm2pgsql-themepark"
git themepark_directory do
  repository "https://github.com/osm2pgsql-dev/osm2pgsql-themepark.git"
  revision node[:spyglass][:themepark][:version]
  user "spyglass"
  group "spyglass"
end

directory "/srv/spyglass.openstreetmap.org/web" do
  user "www-data"
  group "www-data"
  recursive true
  mode "555"
end

directory "/srv/spyglass.openstreetmap.org/data" do
  user "spyglass"
  group "spyglass"
  mode "755"
end

directory "/data" do
  owner "spyglass"
  group "spyglass"
  mode "755"
end

postgresql_user "tomh" do
  cluster node[:spyglass][:database][:cluster]
  superuser true
end

postgresql_user "spyglass" do
  cluster node[:spyglass][:database][:cluster]
  password db_passwords["spyglass"]
end

postgresql_database "spyglass" do
  cluster node[:spyglass][:database][:cluster]
  owner "spyglass"
end

postgresql_extension "postgis" do
  cluster node[:spyglass][:database][:cluster]
  database "spyglass"
end

postgresql_extension "postgis_raster" do
  cluster node[:spyglass][:database][:cluster]
  database "spyglass"
end

postgresql_execute "postgis_gdal_enable_png" do
  command "ALTER DATABASE spyglass SET postgis.gdal_enabled_drivers TO 'PNG';"
  cluster node[:spyglass][:database][:cluster]
  database "spyglass"
  user "postgres"
  group "postgres"
end

systemd_service "spyglass" do
  description "Spyglass server"
  user "spyglass_server"
  after "postgresql.service"
  wants "postgresql.service"
  sandbox :enable_network => true
  #  restrict_address_families "AF_UNIX"
  environment(
    "DATABASE_URL" =>
      "postgres://spyglass:#{db_passwords['spyglass']}@localhost:5432/spyglass?pool_max_conns=8"
  )
  exec_start "/usr/local/bin/spyglass server -disable-timestamp"
end

service "spyglass" do
  action [:enable, :start]
end

systemd_service "replicate" do
  description "Get replication updates"
  user "spyglass"
  after "postgresql.service"
  wants "postgresql.service"
  sandbox :enable_network => true
  restrict_address_families "AF_UNIX"
  read_write_paths ["/srv/spyglass.openstreetmap.org/data/"]
  exec_start "/usr/local/bin/update"
end

systemd_timer "replicate" do
  description "Get replication updates"
  on_boot_sec 60
  on_unit_active_sec 30
  accuracy_sec 5
end

if node[:spyglass][:replication][:enabled]
  service "replicate.timer" do
    action [:enable, :start]
  end
else
  service "replicate.timer" do
    action [:stop, :disable]
  end
end

package %w[
  ruby-pg
  ruby-webrick
]

# TODO: Prometheus not supported by spyglass binary
#
