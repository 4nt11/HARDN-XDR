#!/bin/bash
set -e

is_installed() {
    if command -v apt >/dev/null 2>&1; then
        dpkg -s "$1" >/dev/null 2>&1
    elif command -v dnf >/dev/null 2>&1; then
        dnf list installed "$1" >/dev/null 2>&1
    elif command -v yum >/dev/null 2>&1; then
        yum list installed "$1" >/dev/null 2>&1
    elif command -v rpm >/dev/null 2>&1; then
        rpm -q "$1" >/dev/null 2>&1
    else
        return 1 # Cannot determine package manager
    fi
}

if ! is_installed auditd; then
    HARDN_STATUS "info" "Installing auditd..."
    if command -v apt >/dev/null 2>&1; then
        apt install -y auditd >/dev/null 2>&1
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y auditd >/dev/null 2>&1
    elif command -v yum >/dev/null 2>&1; then
        yum install -y auditd >/dev/null 2>&1
    fi
fi

systemctl daemon-reload
systemctl enable auditd
systemctl restart auditd

HARDN_STATUS "info" "Configuring auditd rules for system security..."

audit_rules_file="/etc/audit/rules.d/hardn-xdr.rules"

cat <<EOF > $audit_rules_file
# auditd-attack
# A Linux Auditd configuration mapped to MITRE's Attack Framework
# Most of my inspiration came from various individuals so I wont name them all, but you're work does not go 
# unnoticed!

### Special Thanks To

#[Eric Gershman](https://github.com/EricGershman/auditd-examples)
#[iase.disa.mil](https://iase.disa.mil/stigs/os/unix-linux/Pages/red-hat.aspx)
#[cyb3rops](https://gist.github.com/Neo23x0/9fe88c0c5979e017a389b90fd19ddfee)
#[ugurengin](https://gist.github.com/ugurengin/4d37ee83e87bc44291f8ae87a00504cd)
#[checkraze](https://github.com/checkraze/auditd-rules/blob/master/auditd.rules)
#[auditdBroFramework](https://github.com/set-element/auditdBroFramework/blob/master/system_config/audit.rules)

# Remove any existing rules
-D

# Buffer Size
## Feel free to increase this if the machine panic's
-b 8192

# Failure Mode
## Possible values: 0 (silent), 1 (printk, print a failure message), 2 (panic, halt the system)
-f 1

# Ignore errors
## e.g. caused by users or files not found in the local environment  
-i 

# Self Auditing ---------------------------------------------------------------

## Audit the audit logs
### Successful and unsuccessful attempts to read information from the audit records
-w /var/log/audit/ -k auditlog

## Auditd configuration
### Modifications to audit configuration that occur while the audit collection functions are operating
-w /etc/audit/ -p wa -k auditconfig
-w /etc/libaudit.conf -p wa -k auditconfig
-w /etc/audisp/ -p wa -k audispconfig

## Monitor for use of audit management tools
-w /sbin/auditctl -p x -k audittools
-w /sbin/auditd -p x -k audittools

# Filters ---------------------------------------------------------------------

### We put these early because audit is a first match wins system.

## Ignore SELinux AVC records
##-a always,exclude -F msgtype=AVC

## Ignore current working directory records
-a always,exclude -F msgtype=CWD

## Ignore EOE records (End Of Event, not needed)
-a always,exclude -F msgtype=EOE

## Cron jobs fill the logs with stuff we normally don't want (works with SELinux)
-a never,user -F subj_type=crond_t
-a exit,never -F subj_type=crond_t

## This prevents chrony from overwhelming the logs
##-a never,exit -F arch=b64 -S adjtimex -F auid=unset -F uid=chrony -F subj_type=chronyd_t

## This is not very interesting and wastes a lot of space if the server is public facing
-a always,exclude -F msgtype=CRYPTO_KEY_USER

## VMWare tools
-a exit,never -F arch=b32 -S fork -F success=0 -F path=/usr/lib/vmware-tools -F subj_type=initrc_t -F exit=-2
-a exit,never -F arch=b64 -S fork -F success=0 -F path=/usr/lib/vmware-tools -F subj_type=initrc_t -F exit=-2

### High Volume Event Filter (especially on Linux Workstations)
-a exit,never -F arch=b32 -F dir=/dev/shm -k sharedmemaccess
-a exit,never -F arch=b64 -F dir=/dev/shm -k sharedmemaccess
-a exit,never -F arch=b32 -F dir=/var/lock/lvm -k locklvm
-a exit,never -F arch=b64 -F dir=/var/lock/lvm -k locklvm


# Rules -----------------------------------------------------------------------

## Kernel Related Events
-w /etc/sysctl.conf -p wa -k sysctl
-a always,exit -F perm=x -F auid!=-1 -F path=/sbin/insmod -k T1215_Kernel_Modules_and_Extensions
-a always,exit -F perm=x -F auid!=-1 -F path=/sbin/modprobe -k T1215_Kernel_Modules_and_Extensions
-a always,exit -F perm=x -F auid!=-1 -F path=/sbin/rmmod -k T1215_Kernel_Modules_and_Extensions
-a always,exit -F arch=b64 -S finit_module -S init_module -S delete_module -F auid!=-1 -k T1215_Kernel_Modules_and_Extensions
-a always,exit -F arch=b32 -S finit_module -S init_module -S delete_module -F auid!=-1 -k T1215_Kernel_Modules_and_Extensions
-w /etc/modprobe.conf -p wa -k T1215_Kernel_Modules_and_Extensions

## Time Related Events
-a exit,always -F arch=b32 -S adjtimex -S settimeofday -S clock_settime -k T1099_Timestomp
-a exit,always -F arch=b64 -S adjtimex -S settimeofday -S clock_settime -k T1099_Timestomp
-a always,exit -F arch=b32 -S clock_settime -k T1099_Timestomp
-a always,exit -F arch=b64 -S clock_settime -k T1099_Timestomp
-w /etc/localtime -p wa -k T1099_Timestomp

## Stunnel 
-w /usr/sbin/stunnel -p x -k T1079_Multilayer_Encryption

## Cron configuration & scheduled jobs related events
-w /etc/cron.allow -p wa -k T1168_Local_Job_Scheduling
-w /etc/cron.deny -p wa -k T1168_Local_Job_Scheduling
-w /etc/cron.d/ -p wa -k T1168_Local_Job_Scheduling
-w /etc/cron.daily/ -p wa -k T1168_Local_Job_Scheduling
-w /etc/cron.hourly/ -p wa -k T1168_Local_Job_Scheduling
-w /etc/cron.monthly/ -p wa -k T1168_Local_Job_Scheduling
-w /etc/cron.weekly/ -p wa -k T1168_Local_Job_Scheduling
-w /etc/crontab -p wa -k T1168_Local_Job_Scheduling
-w /var/spool/cron/crontabs/ -k T1168_Local_Job_Scheduling
-w /etc/inittab -p wa -k T1168_Local_Job_Scheduling
-w /etc/init.d/ -p wa -k T1168_Local_Job_Scheduling
-w /etc/init/ -p wa -k T1168_Local_Job_Scheduling
-w /etc/at.allow -p wa -k T1168_Local_Job_Scheduling
-w /etc/at.deny -p wa -k T1168_Local_Job_Scheduling
-w /var/spool/at/ -p wa -k T1168_Local_Job_Scheduling
-w /etc/anacrontab -p wa -k T1168_Local_Job_Scheduling

## Account Related Events
-w /etc/sudoers -p wa -k T1078_Valid_Accounts
-w /usr/bin/passwd -p x -k T1078_Valid_Accounts
-w /usr/sbin/groupadd -p x -k T1078_Valid_Accounts
-w /usr/sbin/groupmod -p x -k T1078_Valid_Accounts
-w /usr/sbin/addgroup -p x -k T1078_Valid_Accounts
-w /usr/sbin/useradd -p x -k T1078_Valid_Accounts
-w /usr/sbin/usermod -p x -k T1078_Valid_Accounts
-w /usr/sbin/adduser -p x -k T1078_Valid_Accounts

## Privleged Command Execution Related Events
-a exit,always -F arch=b64 -F euid=0 -S execve -k T1078_Valid_Accounts
-a exit,always -F arch=b32 -F euid=0 -S execve -k T1078_Valid_Accounts
-a always,exit -F path=/usr/sbin/userdel -F perm=x -F auid>=500 -F auid!=4294967295 -k T1078_Valid_Accounts
-a always,exit -F path=/bin/ping -F perm=x -F auid>=500 -F auid!=4294967295 -k T1078_Valid_Accounts
-a always,exit -F path=/bin/umount -F perm=x -F auid>=500 -F auid!=4294967295 -k T1078_Valid_Accounts
-a always,exit -F path=/bin/mount -F perm=x -F auid>=500 -F auid!=4294967295 -k T1078_Valid_Accounts
-a always,exit -F path=/bin/su -F perm=x -F auid>=500 -F auid!=4294967295 -k T1078_Valid_Accounts
-a always,exit -F path=/bin/chgrp -F perm=x -F auid>=500 -F auid!=4294967295 -k T1078_Valid_Accounts
-a always,exit -F path=/bin/ping6 -F perm=x -F auid>=500 -F auid!=4294967295 -k T1078_Valid_Accounts
-a always,exit -F path=/sbin/pam_timestamp_check -F perm=x -F auid>=500 -F auid!=4294967295 -k T1078_Valid_Accounts
-a always,exit -F path=/sbin/unix_chkpwd -F perm=x -F auid>=500 -F auid!=4294967295 -k T1078_Valid_Accounts
-a always,exit -F path=/sbin/pwck -F perm=x -F auid>=500 -F auid!=4294967295 -k T1078_Valid_Accounts
-a always,exit -F path=/usr/sbin/suexec -F perm=x -F auid>=500 -F auid!=4294967295 -k T1078_Valid_Accounts
-a always,exit -F path=/usr/sbin/usermod -F perm=x -F auid>=500 -F auid!=4294967295 -k T1078_Valid_Accounts
-a always,exit -F path=/usr/sbin/newusers -F perm=x -F auid>=500 -F auid!=4294967295 -k T1078_Valid_Accounts
-a always,exit -F path=/usr/sbin/groupdel -F perm=x -F auid>=500 -F auid!=4294967295 -k T1078_Valid_Accounts
-a always,exit -F path=/usr/sbin/semanage -F perm=x -F auid>=500 -F auid!=4294967295 -k T1078_Valid_Accounts
-a always,exit -F path=/usr/sbin/usernetctl -F perm=x -F auid>=500 -F auid!=4294967295 -k T1078_Valid_Accounts
-a always,exit -F path=/usr/sbin/ccreds_validate -F perm=x -F auid>=500 -F auid!=4294967295 -k T1078_Valid_Accounts
-a always,exit -F path=/usr/sbin/userhelper -F perm=x -F auid>=500 -F auid!=4294967295 -k T1078_Valid_Accounts
##-a always,exit -F path=/usr/libexec/openssh/ssh-keysign -F perm=x -F auid>=500 -F auid!=4294967295 -k T1078_Valid_Accounts
-a always,exit -F path=/usr/bin/Xorg -F perm=x -F auid>=500 -F auid!=4294967295 -k T1078_Valid_Accounts
-a always,exit -F path=/usr/bin/rlogin -F perm=x -F auid>=500 -F auid!=4294967295 -k T1078_Valid_Accounts
-a always,exit -F path=/usr/bin/sudoedit -F perm=x -F auid>=500 -F auid!=4294967295 -k T1078_Valid_Accounts
-a always,exit -F path=/usr/bin/at -F perm=x -F auid>=500 -F auid!=4294967295 -k T1078_Valid_Accounts
-a always,exit -F path=/usr/bin/rsh -F perm=x -F auid>=500 -F auid!=4294967295 -k T1078_Valid_Accounts
-a always,exit -F path=/usr/bin/gpasswd -F perm=x -F auid>=500 -F auid!=4294967295 -k T1078_Valid_Accounts
-a always,exit -F path=/usr/bin/kgrantpty -F perm=x -F auid>=500 -F auid!=4294967295 -k T1078_Valid_Accounts
-a always,exit -F path=/usr/bin/crontab -F perm=x -F auid>=500 -F auid!=4294967295 -k T1078_Valid_Accounts
-a always,exit -F path=/usr/bin/sudo -F perm=x -F auid>=500 -F auid!=4294967295 -k T1078_Valid_Accounts
-a always,exit -F path=/usr/bin/staprun -F perm=x -F auid>=500 -F auid!=4294967295 -k T1078_Valid_Accounts
-a always,exit -F path=/usr/bin/rcp -F perm=x -F auid>=500 -F auid!=4294967295 -k T1078_Valid_Accounts
-a always,exit -F path=/usr/bin/passwd -F perm=x -F auid>=500 -F auid!=4294967295 -k T1078_Valid_Accounts
-a always,exit -F path=/usr/bin/chsh -F perm=x -F auid>=500 -F auid!=4294967295 -k T1078_Valid_Accounts
-a always,exit -F path=/usr/bin/chfn -F perm=x -F auid>=500 -F auid!=4294967295 -k T1078_Valid_Accounts
-a always,exit -F path=/usr/bin/chage -F perm=x -F auid>=500 -F auid!=4294967295 -k T1078_Valid_Accounts
-a always,exit -F path=/usr/bin/setfacl -F perm=x -F auid>=500 -F auid!=4294967295 -k T1078_Valid_Accounts
-a always,exit -F path=/usr/bin/chacl -F perm=x -F auid>=500 -F auid!=4294967295 -k T1078_Valid_Accounts
-a always,exit -F path=/usr/bin/chcon -F perm=x -F auid>=500 -F auid!=4294967295 -k T1078_Valid_Accounts
-a always,exit -F path=/usr/bin/newgrp -F perm=x -F auid>=500 -F auid!=4294967295 -k T1078_Valid_Accounts
-a always,exit -F path=/usr/bin/newrole -F perm=x -F auid>=500 -F auid!=4294967295 -k T1078_Valid_Accounts
-a always,exit -F path=/usr/bin/kpac_dhcp_helper -F perm=x -F auid>=500 -F auid!=4294967295 -k T1078_Valid_Accounts

## Media Export Related Events
-a always,exit -F arch=b32 -S mount -F auid>=500 -F auid!=4294967295 -k T1052_Exfiltration_Over_Physical_Medium
-a always,exit -F arch=b64 -S mount -F auid>=500 -F auid!=4294967295 -k T1052_Exfiltration_Over_Physical_Medium

## Session Related Events 
-w /var/run/utmp -p wa -k T1108_Redundant_Access
-w /var/log/wtmp -p wa -k T1108_Redundant_Access
-w /var/log/btmp -p wa -k T1108_Redundant_Access

## Login Related Events
-w /var/log/faillog -p wa -k T1021_Remote_Services
-w /var/log/lastlog -p wa -k T1021_Remote_Services
-w /var/log/tallylog -p wa -k T1021_Remote_Services

## Pam Related Events
-w /etc/pam.d/ -p wa -k T1071_Standard_Application_Layer_Protocol
-w /etc/security/limits.conf -p wa  -k T1071_Standard_Application_Layer_Protocol
-w /etc/security/pam_env.conf -p wa -k T1071_Standard_Application_Layer_Protocol
-w /etc/security/namespace.conf -p wa -k T1071_Standard_Application_Layer_Protocol
-w /etc/security/namespace.init -p wa -k T1071_Standard_Application_Layer_Protocol
-w /etc/pam.d/common-password -p wa -k T1201_Password_Policy_Discovery

## SSH Related Events
-w /etc/ssh/sshd_config -k T1021_Remote_Services

##C2 Releated Events
#Log 64 bit processes (a2!=6e filters local unix socket calls)
-a exit,always -F arch=b64 -S connect -F a2!=110 -k T1043_Commonly_Used_Port

#Log 32 bit processes (a0=3 means only outbound sys_connect calls)
-a exit,always -F arch=b32 -S socketcall -F a0=3 -k T1043_Commonly_Used_Port

## Priv Escalation Related Events
-w /bin/su -p x -k T1169_Sudo
-w /usr/bin/sudo -p x -k T1169_Sudo
-w /etc/sudoers -p rw -k T1169_Sudo
-a always,exit -F dir=/home -F uid=0 -F auid>=1000 -F auid!=4294967295 -C auid!=obj_uid -k T1169_Sudo
-a always,exit -F arch=b32 -S chmod -F auid>=500 -F auid!=4294967295 -k T1166_Seuid_and_Setgid
-a always,exit -F arch=b32 -S chown -F auid>=500 -F auid!=4294967295 -k T1166_Seuid_and_Setgid
-a always,exit -F arch=b32 -S fchmod -F auid>=500 -F auid!=4294967295 -k T1166_Seuid_and_Setgid
-a always,exit -F arch=b32 -S fchmodat -F auid>=500 -F auid!=4294967295 -k T1166_Seuid_and_Setgid
-a always,exit -F arch=b32 -S fchown -F auid>=500 -F auid!=4294967295 -k T1166_Seuid_and_Setgid
-a always,exit -F arch=b32 -S fchownat -F auid>=500 -F auid!=4294967295 -k T1166_Seuid_and_Setgid
-a always,exit -F arch=b32 -S fremovexattr -F auid>=500 -F auid!=4294967295 -k T1166_Seuid_and_Setgid
-a always,exit -F arch=b32 -S fsetxattr -F auid>=500 -F auid!=4294967295 -k T1166_Seuid_and_Setgid
-a always,exit -F arch=b32 -S lchown -F auid>=500 -F auid!=4294967295 -k T1166_Seuid_and_Setgid
-a always,exit -F arch=b32 -S lremovexattr -F auid>=500 -F auid!=4294967295 -k T1166_Seuid_and_Setgid
-a always,exit -F arch=b32 -S lsetxattr -F auid>=500 -F auid!=4294967295 -k T1166_Seuid_and_Setgid
-a always,exit -F arch=b32 -S removexattr -F auid>=500 -F auid!=4294967295 -k T1166_Seuid_and_Setgid
-a always,exit -F arch=b32 -S setxattr -F auid>=500 -F auid!=4294967295 -k T1166_Seuid_and_Setgid
-a always,exit -F arch=b64 -S chmod  -F auid>=500 -F auid!=4294967295 -k T1166_Seuid_and_Setgid
-a always,exit -F arch=b64 -S chown -F auid>=500 -F auid!=4294967295 -k T1166_Seuid_and_Setgid
-a always,exit -F arch=b64 -S fchmod -F auid>=500 -F auid!=4294967295 -k T1166_Seuid_and_Setgid
-a always,exit -F arch=b64 -S fchmodat -F auid>=500 -F auid!=4294967295 -k T1166_Seuid_and_Setgid
-a always,exit -F arch=b64 -S fchown -F auid>=500 -F auid!=4294967295 -k T1166_Seuid_and_Setgid
-a always,exit -F arch=b64 -S fchownat -F auid>=500 -F auid!=4294967295 -k T1166_Seuid_and_Setgid
-a always,exit -F arch=b64 -S fremovexattr -F auid>=500 -F auid!=4294967295 -k T1166_Seuid_and_Setgid
-a always,exit -F arch=b64 -S fsetxattr -F auid>=500 -F auid!=4294967295 -k T1166_Seuid_and_Setgid
-a always,exit -F arch=b64 -S lchown -F auid>=500 -F auid!=4294967295 -k T1166_Seuid_and_Setgid
-a always,exit -F arch=b64 -S lremovexattr -F auid>=500 -F auid!=4294967295 -k T1166_Seuid_and_Setgid
-a always,exit -F arch=b64 -S lsetxattr -F auid>=500 -F auid!=4294967295 -k T1166_Seuid_and_Setgid
-a always,exit -F arch=b64 -S removexattr -F auid>=500 -F auid!=4294967295 -k T1166_Seuid_and_Setgid
-a always,exit -F arch=b64 -S setxattr -F auid>=500 -F auid!=4294967295 -k T1166_Seuid_and_Setgid
-a always,exit -F arch=b64 -C auid!=uid -S execve -k T1166_Seuid_and_Setgid
-a always,exit -F arch=b32 -C auid!=uid -S execve -k T1166_Seuid_and_Setgid
-a always,exit -F arch=b64 -S setuid -S setgid -S setreuid -S setregid -k T1166_Seuid_and_Setgid
-a always,exit -F arch=b32 -S setuid -S setgid -S setreuid -S setregid -k T1166_Seuid_and_Setgid
-a always,exit -F arch=b64 -S setuid -S setgid -S setreuid -S setregid -F exit=EPERM -k T1166_Seuid_and_Setgid
-a always,exit -F arch=b32 -S setuid -S setgid -S setreuid -S setregid -F exit=EPERM -k T1166_Seuid_and_Setgid
 -w /usr/bin/ -p wa -k T1068_Exploitation_for_Privilege_Escalation

## Recon Related Events
-w /etc/group -p wa -k T1087_Account_Discovery
-w /etc/passwd -p wa -k TT1087_Account_Discovery
-w /etc/gshadow -k T1087_Account_Discovery
-w /etc/shadow -k T1087_Account_Discovery
-w /etc/security/opasswd -k T1087_Account_Discovery
-w /usr/sbin/nologin -k T1087_Account_Discovery
-w /sbin/nologin -k T1087_Account_Discovery
-w /usr/bin/whoami -p x -k T1033_System_Owner_User_Discovery
-w /etc/hostname -p r -k T1082_System_Information_Discovery
-w /sbin/iptables -p x -k T1082_System_Information_Discovery
-w /sbin/ifconfig -p x -k T1082_System_Information_Discovery
-w /etc/login.defs -p wa -k T1082_System_Information_Discovery
-w /etc/resolv.conf -k T1016_System_Network_Configuration_Discovery
-w /etc/hosts.allow -k T1016_System_Network_Configuration_Discovery
-w /etc/hosts.deny -k T1016_System_Network_Configuration_Discovery
-w /etc/securetty -p wa -k T1082_System_Information_Discovery
-w /var/log/faillog -p wa -k T1082_System_Information_Discovery
-w /var/log/lastlog -p wa -k T1082_System_Information_Discovery
-w /var/log/tallylog -p wa -k T1082_System_Information_Discovery
-w /usr/sbin/tcpdump -p x -k T1049_System_Network_Connections_discovery
-w /usr/sbin/traceroute -p x -k T1049_System_Network_Connections_discovery
-w /usr/bin/wireshark -p x -k T1049_System_Network_Connections_discovery
-w /usr/bin/rawshark -p x -k T1049_System_Network_Connections_discovery
-w /usr/bin/grep -p x -k T1081_Credentials_In_Files
-w /usr/bin/egrep -p x -k T1081_Credentials_In_Files
-w /usr/bin/ps -p x -k T1057_Process_Discovery

## Data Copy(Local)
-w /usr/bin/cp -p x -k T1005_Data_from_Local_System
-w /usr/bin/dd -p x -k T1005_Data_from_Local_System

## Remote Access Related Events
-w /usr/bin/wget -p x -k T1219_Remote_Access_Tools
-w /usr/bin/curl -p x -k T1219_Remote_Access_Tools
-w /usr/bin/base64 -p x -k T1219_Remote_Access_Tools
-w /bin/nc -p x -k T1219_Remote_Access_Tools
-w /bin/netcat -p x -k T1219_Remote_Access_Tools
-w /usr/bin/ncat -p x -k T1219_Remote_Access_Tools
-w /usr/bin/ssh -p x -k T1219_Remote_Access_Tools
-w /usr/bin/socat -p x -k T1219_Remote_Access_Tools
-w /usr/bin/rdesktop -p x -k T1219_Remote_Access_Tools

##Third Party Software 
# RPM (Redhat/CentOS)
-w /usr/bin/rpm -p x -k T1072_third_party_software
-w /usr/bin/yum -p x -k T1072_third_party_software

# YAST/Zypper/RPM (SuSE)
-w /sbin/yast -p x -k T1072_third_party_software
-w /sbin/yast2 -p x -k T1072_third_party_software
-w /bin/rpm -p x -k T1072_third_party_software
-w /usr/bin/zypper -k T1072_third_party_software

# DPKG / APT-GET (Debian/Ubuntu)
-w /usr/bin/dpkg -p x -k T1072_third_party_software
-w /usr/bin/apt-add-repository -p x -k T1072_third_party_software
-w /usr/bin/apt-get -p x -k T1072_third_party_software
-w /usr/bin/aptitude -p x -k T1072_third_party_software

## Code injection Related Events
-a always,exit -F arch=b32 -S ptrace -k T1055_Process_Injection
-a always,exit -F arch=b64 -S ptrace -k T1055_Process_Injection
-a always,exit -F arch=b32 -S ptrace -F a0=0x4 -k T1055_Process_Injection
-a always,exit -F arch=b64 -S ptrace -F a0=0x4 -k T1055_Process_Injection
-a always,exit -F arch=b32 -S ptrace -F a0=0x5 -k T1055_Process_Injection
-a always,exit -F arch=b64 -S ptrace -F a0=0x5 -k T1055_Process_Injection
-a always,exit -F arch=b32 -S ptrace -F a0=0x6 -k T1055_Process_Injection
-a always,exit -F arch=b64 -S ptrace -F a0=0x6 -k T1055_Process_Injection

## Shell configuration Persistence Related Events
-w /etc/profile.d/ -k T1156_bash_profile_and_bashrc
-w /etc/profile -k T1156_bash_profile_and_bashrc
-w /etc/shells -k T1156_bash_profile_and_bashrc
-w /etc/bashrc -k T1156_bash_profile_and_bashrc
-w /etc/csh.cshrc -k T1156_bash_profile_and_bashrc
-w /etc/csh.login -k T1156_bash_profile_and_bashrc

#Log all commands (Noisy)
#-a exit,always -F arch=b64 -S execve -k T1059_CommandLine_Interface
#-a exit,always -F arch=b32 -S execve -k T1059_CommandLine_Interface

#Remote File Copy
-w /usr/bin/ftp -p x -k T1105_remote_file_copy

## File Deletion by User Related Events
-a always,exit -F arch=b32 -S rmdir -S unlink -S unlinkat -S rename -S renameat -F auid>=500 -F auid!=4294967295 -k T1107_File_Deletion
-a always,exit -F arch=b64 -S rmdir -S unlink -S unlinkat -S rename -S renameat -F auid>=500 -F auid!=4294967295 -k T1107_File_Deletion
-a always,exit -F arch=b32 -S rmdir -S unlink -S unlinkat -S rename -S renameat -F auid=0 -k T1070_Indicator_Removal_on_Host 
-a always,exit -F arch=b64 -S rmdir -S unlink -S unlinkat -S rename -S renameat -F auid=0 -k T1070_Indicator_Removal_on_Host 

# Make the configuration immutable --------------------------------------------
##-e 2
EOF

# Secure the audit rules file permissions
chmod 600 "$audit_rules_file"
chown root:root "$audit_rules_file"

# Reload auditd rules
augenrules --load 2>/dev/null || service auditd restart
