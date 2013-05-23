package "nginx"

# Render nginx default vhost config
template "/etc/nginx/conf.d/default.conf" do
  owner "root"
  group "root"
  mode 0644
  source "nginx.default.conf.erb"
  notifies :restart, "service[nginx]"
  variables(
    :hostname => node['hostname'],
    :gitlab_app_home => node['gitlab']['app_home'],
    :https_boolean => node['gitlab']['https'],
    :ssl_certificate => node['gitlab']['ssl_certificate'],
    :ssl_certificate_key => node['gitlab']['ssl_certificate_key']
  )
end

