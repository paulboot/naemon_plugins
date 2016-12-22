# naemon_plugins

Collection of useful check plugins

Example config how to test proxy downloads, the HTTP GET haeder is tricky to get it right. In this example once every hour a 10MiB file is downloaded from a fictive test server.

```
define service {
  service_description            PROXY-100MB
  hostgroup_name                 firewallhosts
  use                            local-service,service-pnp
  check_command                  check_proxy!20!40!10MiB.bin
  check_interval                 60
  max_check_attempts             1
}

define command {
  command_name                   check_proxy
  command_line                   /usr/local/lib/nagios/plugins/check_http -w $ARG1$ -c $ARG2$ -t 30 -I $HOSTADDRESS$ -p 8080 -H download.test.com -u http://download.test.com/test/$ARG3$
}
```
