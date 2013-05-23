#
# Cookbook Name:: gitlab
# Recipe:: default
#
# Copyright 2012, Gerald L. Hevener Jr., M.S.
# Copyright 2012, Eric G. Wolfe
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# Include cookbook dependencies
%w{ ruby_build build-essential
    readline sudo openssh xml zlib python::package python::pip
    redisio::install redisio::enable }.each do |requirement|
  include_recipe requirement
end

case node['platform_family']
when "rhel"
  include_recipe "yumrepo::epel"
end

# symlink redis-cli into /usr/bin (needed for gitlab hooks to work)
link "/usr/bin/redis-cli" do
  to "/usr/local/bin/redis-cli"
end

# There are problems deploying on Redhat provided rubies.
# We'll use Fletcher Nichol's slick ruby_build cookbook to compile a Ruby.
if node['gitlab']['install_ruby'] !~ /package/
  ruby_build_ruby node['gitlab']['install_ruby']

  # Drop off a profile script.
  template "/etc/profile.d/gitlab.sh" do
    owner "root"
    group "root"
    mode 0755
    variables(
      :fqdn => node['fqdn'],
      :install_ruby => node['gitlab']['install_ruby']
    )
  end

  # Set PATH for remainder of recipe.
  ENV['PATH'] = "/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin:/root/bin:/usr/local/ruby/#{node['gitlab']['install_ruby']}/bin"
end

# Install required packages for Gitlab
node['gitlab']['packages'].each do |pkg|
  package pkg
end

# Install sshkey gem into chef
chef_gem "sshkey" do
  action :install
end

# Install required Ruby Gems for Gitlab
%w{ charlock_holmes bundler }.each do |gempkg|
  gem_package gempkg do
    action :install
  end
end

# Install gitlab shell
include_recipe "gitlab::shell"

# Install pygments from pip
python_pip "pygments" do
  action :install
end

# Add the gitlab user
user node['gitlab']['user'] do
  home node['gitlab']['home']
  shell "/bin/bash"
  supports :manage_home => true
end

# Fix home permissions for nginx
directory node['gitlab']['home'] do
  owner node['gitlab']['user']
  group node['gitlab']['group']
  mode 0755
end

# # Add the gitlab user to the "git" group
# group node['gitlab']['git_group'] do
#   members node['gitlab']['user']
# end

# Create a $HOME/.ssh folder
directory "#{node['gitlab']['home']}/.ssh" do
  owner node['gitlab']['user']
  group node['gitlab']['group']
  mode 0700
end

# Generate and deploy ssh public/private keys
Gem.clear_paths
require 'sshkey'
gitlab_sshkey = SSHKey.generate(:type => 'RSA', :comment => "#{node['gitlab']['user']}@#{node['fqdn']}")
node.set_unless['gitlab']['public_key'] = gitlab_sshkey.ssh_public_key

# Save public_key to node, unless it is already set.
ruby_block "save node data" do
  block do
    node.save
  end
  not_if { Chef::Config[:solo] }
  action :create
end

# Render private key template
template "#{node['gitlab']['home']}/.ssh/id_rsa" do
  owner node['gitlab']['user']
  group node['gitlab']['group']
  variables(
    :private_key => gitlab_sshkey.private_key
  )
  mode 0600
  not_if { File.exists?("#{node['gitlab']['home']}/.ssh/id_rsa") }
end

# Render public key template for gitlab user
template "#{node['gitlab']['home']}/.ssh/id_rsa.pub" do
  owner node['gitlab']['user']
  group node['gitlab']['group']
  mode 0644
  variables(
    :public_key => node['gitlab']['public_key']
  )
  not_if { File.exists?("#{node['gitlab']['home']}/.ssh/id_rsa.pub") }
end

# Render public key template for gitolite user
template "#{node['gitlab']['git_home']}/gitlab.pub" do
  source "id_rsa.pub.erb"
  owner node['gitlab']['git_user']
  group node['gitlab']['git_group']
  mode 0644
  variables(
    :public_key => node['gitlab']['public_key']
  )
  not_if { File.exists?("#{node['gitlab']['git_home']}/gitlab.pub") }
end

# Configure gitlab user to auto-accept localhost SSH keys
template "#{node['gitlab']['home']}/.ssh/config" do
  source "ssh_config.erb"
  owner node['gitlab']['user']
  group node['gitlab']['group']
  mode 0644
  variables(
    :fqdn => node['fqdn'],
    :trust_local_sshkeys => node['gitlab']['trust_local_sshkeys']
  )
end

# Clone Gitlab repo from github
git node['gitlab']['app_home'] do
  repository node['gitlab']['gitlab_url']
  reference node['gitlab']['gitlab_branch']
  action :checkout
  user node['gitlab']['user']
  group node['gitlab']['group']
end

%w{ tmp tmp/pids tmp/cache log }.each do |d|
  directory "#{node['gitlab']['app_home']}/#{d}" do
    user node['gitlab']['user']
    group node['gitlab']['group']
    mode "0755"
    action :create
    recursive true
  end
end

# Render gitlab config files
%w{ gitlab.yml puma.rb }.each do |cfg|
  template "#{node['gitlab']['app_home']}/config/#{cfg}" do
    owner node['gitlab']['user']
    group node['gitlab']['group']
    mode 0644
    variables(
      :fqdn => node['fqdn'],
      :https_boolean => node['gitlab']['https'],
      :git_user => node['gitlab']['git_user'],
      :git_home => node['gitlab']['git_home'],
      :backup_path => node['gitlab']['backup_path'],
      :backup_keep_time => node['gitlab']['backup_keep_time']
    )
  end
end

# # Setup the database
# case node['gitlab']['database']['type']
# when 'mysql'
#   include_recipe 'gitlab::mysql'
# when 'postgres'
#   include_recipe 'gitlab::postgres'
# else
#   Chef::Log.error "#{node['gitlab']['database']['type']} is not a valid type. Please use 'mysql' or 'postgres'!"
# end

# Create the backup directory
directory node['gitlab']['backup_path'] do
  owner node['gitlab']['user']
  group node['gitlab']['group']
  mode 00755
  action :create
end

# Write the database.yml
template "#{node['gitlab']['app_home']}/config/database.yml" do
  source 'database.yml.erb'
  owner node['gitlab']['user']
  group node['gitlab']['group']
  mode '0644'
  variables(
    :adapter  => node['gitlab']['database']['adapter'],
    :encoding => node['gitlab']['database']['encoding'],
    :host     => node['gitlab']['database']['host'],
    :database => node['gitlab']['database']['database'],
    :pool     => node['gitlab']['database']['pool'],
    :username => node['gitlab']['database']['username'],
    :password => node['gitlab']['database']['password']
  )
end

without_group = node['gitlab']['database']['type'] == 'mysql' ? 'postgres' : 'mysql'

# Install Gems with bundle install
execute "gitlab-bundle-install" do
  command "bundle install --without development test #{without_group} --deployment"
  cwd node['gitlab']['app_home']
  user node['gitlab']['user']
  group node['gitlab']['group']
  environment({ 'LANG' => "en_US.UTF-8", 'LC_ALL' => "en_US.UTF-8" })
  not_if { File.exists?("#{node['gitlab']['app_home']}/vendor/bundle") }
end

# bash "set permissions" do
#   code <<-EOF
#   setfacl -R -d -m u:#{node['gitlab']['git_user']}:rwX #{node['gitlab']['git_home']}/repositories
#   setfacl -R -d -m u:#{node['gitlab']['user']}:rwX #{node['gitlab']['git_home']}/repositories
#   setfacl -R -m u:#{node['gitlab']['git_user']}:rwX #{node['gitlab']['git_home']}/repositories
#   setfacl -R -m u:#{node['gitlab']['user']}:rwX #{node['gitlab']['git_home']}/repositories
#   EOF
#   not_if { File.exists?("#{node['gitlab']['app_home']}/.gitlab-setup") }
# end

# Setup sqlite database for Gitlab
execute "gitlab-bundle-rake" do
  command "echo 'yes'|bundle exec rake gitlab:setup RAILS_ENV=production && touch .gitlab-setup"
  cwd node['gitlab']['app_home']
  user node['gitlab']['user']
  group node['gitlab']['group']
  not_if { File.exists?("#{node['gitlab']['app_home']}/.gitlab-setup") }
end

template "/etc/init.d/gitlab" do
  source "gitlab.init.erb"
  mode "0755"
end

service "gitlab" do
  action [:enable, :start]
  supports status: true, restart: true
end

case node['gitlab']['http_proxy']['variant']
when "nginx"
  include_recipe "gitlab::proxy_nginx"
when "apache2"
  include_recipe "gitlab::proxy_apache2"
end
