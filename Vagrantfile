Vagrant.require_version "= 2.4.9"

nodes = {
  "lb"      => { ip: "192.168.56.10", memory: 512,  cpus: 1 },
  "cp1"     => { ip: "192.168.56.11", memory: 2048, cpus: 2 },
  "worker1" => { ip: "192.168.56.21", memory: 3072, cpus: 2 },
  "worker2" => { ip: "192.168.56.22", memory: 3072, cpus: 2 }
}

Vagrant.configure("2") do |config|
  config.vm.box = "bento/ubuntu-24.04"
  config.vm.box_version = "202508.03.0"
  config.vm.box_architecture = "amd64"
  config.vm.box_check_update = false
  config.vm.synced_folder ".", "/vagrant", disabled: true
  config.ssh.insert_key = true

  config.vm.provider :libvirt do |libvirt|
    libvirt.uri = "qemu:///system"
    libvirt.driver = "kvm"
    libvirt.management_network_name = "dpg-management"
    libvirt.management_network_address = "192.168.121.0/24"
    libvirt.management_network_mode = "nat"
  end

  nodes.each do |name, settings|
    config.vm.define name do |node|
      node.vm.hostname = name
      node.vm.network "private_network",
        ip: settings[:ip],
        netmask: "255.255.255.0",
        libvirt__network_name: "dpg-lab",
        libvirt__dhcp_enabled: false,
        libvirt__forward_mode: "none"

      node.vm.provider :libvirt do |libvirt|
        libvirt.memory = settings[:memory]
        libvirt.cpus = settings[:cpus]
      end
    end
  end
end
