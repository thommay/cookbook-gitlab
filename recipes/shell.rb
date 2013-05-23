#
# Cookbook Name:: gitlab-shell
# Recipe:: default
#
# Copyright 2010, RailsAnt, Inc.
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
#
%w{ git perl }.each do |cb_include|
  include_recipe cb_include
end

# Add git user
# Password isn't set correctly in original recipe, and really no reason to set one.
user node['gitlab']['git_user'] do
  comment "Git User" 
  home node['gitlab']['git_home']
  shell "/bin/bash" 
  supports :manage_home => true
end

directory node['gitlab']['git_home'] do
  owner node['gitlab']['git_user']
  group node['gitlab']['git_group']
  mode 0750
end

directory "#{node['gitlab']['git_home']}/bin" do
  owner node['gitlab']['git_user']
  group node['gitlab']['git_group']
  mode 0775
end

directory "#{node['gitlab']['git_home']}/repositories" do
  owner node['gitlab']['git_user']
  group node['gitlab']['git_group']
  mode 2770
end

# Create a $HOME/.ssh folder
directory "#{node['gitlab']['git_home']}/.ssh" do
  owner node['gitlab']['git_user']
  group node['gitlab']['git_group']
  mode 0700
end

# Clone gitlab-shell repo from github
git node['gitlab']['shell_home'] do
  repository node['gitlab']['shell_url']
  reference node['gitlab']['shell_branch']
  user node['gitlab']['git_user']
  group node['gitlab']['git_group']
  action :checkout
end

template "#{node['gitlab']['shell_home']}/config.yml" do
  source "config-shell.yml.erb"
  owner node['gitlab']['git_user']
  group node['gitlab']['git_group']
end

# gitlab-shell application install script
execute "shell-install" do
  user node['gitlab']['git_user']
  cwd node['gitlab']['git_home']
  command "#{node['gitlab']['shell_home']}/bin/install"
end
