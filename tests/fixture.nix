{
  dataPool,
  rootDisk2,
  sshBootPort,
  sshPort,
  staticNetwork,
  system,
}:
{
  host = {
    name = "myskarabox";
    username = "skarabox";
    ip = "10.0.2.2";
    hostId = "00000000";
    machineId = "0123456789abcdef0123456789abcdef";
    inherit
      sshBootPort
      sshPort
      staticNetwork
      system
      ;
  };
  disks = {
    rootPool = {
      disk1 = "/dev/nvme0n1";
      disk2 = if rootDisk2 then "/dev/nvme1n1" else null;
      reservation = "500M";
    };
    dataPool = {
      enable = dataPool;
      disk1 = "/dev/sda";
      disk2 = "/dev/sdb";
      reservation = "10G";
    };
  };
  files = {
    clientPrivateKey = ./fixtures/insecure-test-client-key;
    clientPublicKey = ./fixtures/insecure-test-client-key.pub;
    facter = ./fixtures/qemu-facter.json;
    hostPrivateKey = ./fixtures/insecure-test-ssh-key;
    hostPublicKey = ./fixtures/insecure-test-ssh-key.pub;
    secrets = ./fixtures/insecure-generated-secrets.yaml;
    sopsPrivateKey = ./fixtures/insecure-test-sops-key;
  };
}
