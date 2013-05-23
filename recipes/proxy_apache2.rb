include_recipe "apache2"

apache_module "proxy"
apache_module "proxy_http"

include_recipe "apache2::mod_ssl" if node['gitlab']['https']

template "#{node['apache']['dir']}/sites-available/gitlab" do
  source      "apache_gitlab.erb"
  owner       'root'
  group       'root'
  mode        '0644'
  variables(
    :host_name     => node['gitlab']['http_proxy']['host_name'],
    :host_aliases     => node['gitlab']['http_proxy']['host_aliases'],
    :listen_ports     => node['gitlab']['http_proxy']['listen_ports'],
    :ca_file          => node['gitlab']['ssl_ca_file'],
    :ca_chain_file    => node['gitlab']['ssl_ca_chain_file'],
    :ssl_certificate  => node['gitlab']['ssl_certificate'],
    :ssl_certificate_key => node['gitlab']['ssl_certificate_key'],
  )

  if File.exists?("#{node['apache']['dir']}/sites-enabled/jenkins")
    notifies  :restart, 'service[apache2]'
  end
end


apache_site "000-default" do
  enable  false
end

apache_site "gitlab" do
  if node['gitlab']['http_proxy']['variant'] == "apache2"
    enable true
  else
    enable false
  end
end
