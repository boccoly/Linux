# 6 — Services

Only for services this image actually runs. Check the README for which ones are required — a required service gets hardened, an unrequired one gets removed.

```sh
sudo ss -tulpn                                   # what's listening
systemctl list-units --type=service --state=running
```

**Restart the service after every config change**, or the change doesn't count.

## SSH — `/etc/ssh/sshd_config`

```
PermitRootLogin no
PasswordAuthentication yes        # unless README says key-only
PermitEmptyPasswords no
Protocol 2
X11Forwarding no
MaxAuthTries 3
LoginGraceTime 30
ClientAliveInterval 300
ClientAliveCountMax 0
UsePAM yes
IgnoreRhosts yes
HostbasedAuthentication no
PermitUserEnvironment no
LogLevel VERBOSE
Banner /etc/issue.net
```
```sh
sudo sshd -t && sudo systemctl restart ssh
```
Always `sshd -t` before restarting — it catches syntax errors before they lock you out.

Also check `/etc/ssh/sshd_config.d/` for overrides.

## FTP (vsftpd) — `/etc/vsftpd.conf`

```
anonymous_enable=NO
local_enable=YES
write_enable=NO                  # unless the README requires uploads
chroot_local_user=YES
ssl_enable=YES
force_local_data_ssl=YES
force_local_logins_ssl=YES
xferlog_enable=YES
ftpd_banner=Authorized users only
```
```sh
sudo systemctl restart vsftpd
```

`/etc/ftpusers` lists users **denied** FTP access. Scoring reports often reference a specific user being allowed or denied — read the README carefully on this one.

## Apache — `/etc/apache2/`

```
ServerTokens Prod
ServerSignature Off
TraceEnable Off
```
```sh
sudo a2enmod headers ssl
sudo apachectl configtest && sudo systemctl reload apache2
```

Check:
- `/etc/apache2/sites-enabled/` and `conf-enabled/` for anything unexpected
- `.htaccess` files under the web root
- Web root ownership: `sudo chown -R root:www-data /var/www && sudo chmod -R 750 /var/www`
- Web shells: `grep -rniE 'eval\(|base64_decode|system\(|shell_exec|passthru' /var/www`

## Nginx — `/etc/nginx/`

```
server_tokens off;
```
```sh
sudo nginx -t && sudo systemctl reload nginx
```

## MySQL / MariaDB

```sh
sudo mysql_secure_installation
```
Then check for an auth bypass:
```sh
sudo grep -rn 'skip-grant-tables' /etc/mysql/
```
In `/etc/mysql/mysql.conf.d/mysqld.cnf`:
```
bind-address = 127.0.0.1
local-infile = 0
```
```sh
sudo systemctl restart mysql
```

## Samba — `/etc/samba/smb.conf`

```
[global]
   restrict anonymous = 2
   server min protocol = SMB2
   guest ok = no
```
```sh
sudo testparm && sudo systemctl restart smbd nmbd
```

## PHP — `/etc/php/<ver>/apache2/php.ini`

```
expose_php = Off
display_errors = Off
allow_url_fopen = Off
allow_url_include = Off
disable_functions = exec,passthru,shell_exec,system,proc_open,popen
```
Check every SAPI directory (`apache2/`, `cli/`, `fpm/`) — they have separate `php.ini` files.

## Removing a service entirely

If the README doesn't require it:
```sh
sudo systemctl disable --now <service>
sudo apt purge -y <package>
```
Purging is usually what scores, not just stopping.
