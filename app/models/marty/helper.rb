class Marty::Helper
  include Delorean::Model

  delorean_fn :sleep, sig: 1 do
    |seconds|
    Kernel.sleep seconds
  end

  delorean_fn :my_ip, sig:0 do
    Socket.ip_address_list.detect{|intf| intf.ipv4_private?}.ip_address
  end

  delorean_fn :git, sig:0 do
    [my_ip, ENV['DELAYED_VER']]
  end

  delorean_fn :range_step, sig: 3 do
    |rstart, rend, step|
    (rstart..rend).step(step).to_a
  end
end