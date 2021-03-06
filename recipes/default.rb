#
# Cookbook Name:: ganeti
# Recipe:: default
#
# Copyright (C) 2015 Oregon State University
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
case node['platform']
# FC024: Need to use platform here since we don't have a PPA for Debian
when 'rhel', 'centos'
  include_recipe 'yum-epel'
  include_recipe 'yum-elrepo'
  yum_repository 'ganeti' do
    repositoryid 'ganeti'
    description node['ganeti']['yum']['description']
    url node['ganeti']['yum']['uri']
    gpgcheck node['ganeti']['yum']['gpgcheck']
    gpgkey node['ganeti']['yum']['gpgkey']
    action :add
  end
when 'ubuntu'
  include_recipe 'apt'
  apt_repository 'ganeti' do
    uri 'http://ppa.launchpad.net/pkg-ganeti-devel/lts/ubuntu '
    distribution node['lsb']['codename']
    components ['main']
    keyserver 'keyserver.ubuntu.com'
    key '38520275'
  end
end

include_recipe 'lvm'

packages = node['ganeti']['packages'][node['ganeti']['hypervisor']] +
           node['ganeti']['packages']['common']

packages.each { |p| package p }

# load/configure drbd/kvm modules
include_recipe 'modules'

package node['ganeti']['package_name'] do
  version node['ganeti']['version'] if node['ganeti']['version']
end

# Ensure these directories exist
%w(/root/.ssh /var/lib/ganeti/rapi).each do |d|
  directory d do
    owner 'root'
    group 'root'
    mode 0750
    recursive true
    action :create
  end
end

# Initialize cluster if set as a master-node
execute 'ganeti-initialize' do
  cluster = node['ganeti']['cluster']
  disk_templates = cluster['disk-templates'].join(',')
  hypervisors = cluster['enabled-hypervisors'].join(',')
  nic_mode = cluster['nic']['mode']
  nic_link = cluster['nic']['link']
  command [
    "#{node['ganeti']['bin-path']}/gnt-cluster init",
    "--enabled-disk-templates=#{disk_templates}",
    "--master-netdev=#{cluster['master-netdev']}",
    "--enabled-hypervisors=#{hypervisors}",
    "-N mode=#{nic_mode},link=#{nic_link}",
    cluster['extra-opts'], cluster['name']].join(' ')
  creates '/var/lib/ganeti/config.data'
  only_if do
    node['fqdn'] == node['ganeti']['master-node'] ||
      node['ganeti']['master-node'] == true
  end
end

service 'ganeti' do
  supports status: true, restart: true
  action [:enable, :start]
end

# Disable drbd service, ganeti manages it directly
service 'drbd' do
  action [:disable, :stop]
end

cookbook_file '/etc/cron.d/ganeti' do
  source 'ganeti-cron'
  owner 'root'
  group 'root'
  mode '0644'
end

cookbook_file '/etc/lvm/lvm.conf' do
  source 'lvm.conf'
  owner 'root'
  group 'root'
  mode '0644'
end

begin
  rapi = Chef::EncryptedDataBagItem.load(
    'ganeti', node['ganeti']['data_bag']['rapi_users'])

  file '/var/lib/ganeti/rapi/users' do
    owner 'root'
    group 'root'
    mode 0640
    content rapi_users(rapi.to_hash)
  end
rescue
  Chef::Log.info('No rapi_users data bag, skipping')
end
