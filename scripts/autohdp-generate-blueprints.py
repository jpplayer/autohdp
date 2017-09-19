#!/usr/bin/python

import sys
import json

trust_realm = None
trust_kdc = None

blueprint_source = sys.argv[1]
blueprint_target = sys.argv[2]
version_short = sys.argv[3]
security_type = sys.argv[4]
realm = sys.argv[5]
kdc = sys.argv[6]

#if len(sys.argv) >= 7:
#	trust_realm = sys.argv[6]
#	trust_kdc = sys.argv[7]

jsonFile = open( blueprint_source, "r")
b = json.load( jsonFile )
jsonFile.close()

krb_snip_env = """
{
      "kerberos-env": {
        "properties_attributes" : { },
        "properties" : {
          "realm" : "AMBARI.APACHE.ORG",
          "kdc_type" : "mit-kdc",
          "kdc_hosts" : "(kerberos_server_name)",
          "admin_server_host" : "(kerberos_server_name)"
        }
      }
}
"""

krb_snip_conf = """
    {
      "krb5-conf": {
        "properties_attributes" : { },
        "properties" : {
          "domains" : "",
          "manage_krb5_conf" : "true"
        }
      }
    }
"""
snip = json.loads( krb_snip_env )
snip["kerberos-env"]["properties"]["realm"] = realm
snip["kerberos-env"]["properties"]["admin_server_host"] = kdc
snip["kerberos-env"]["properties"]["kdc_hosts"] = kdc
b["configurations"].append ( snip )

if security_type == "NONE":
	b["Blueprints"]["security"] = { "type" :"KERBEROS" }


snip = json.loads( krb_snip_conf )
#domain = kdc [ kdc.index(".") : ]
#snip["krb5-conf"]["properties"]["domains"] = "*" + domain + " = " + realm 

if trust_realm:
	b["Blueprints"]["security"]["properties"] = { "additional_realms" : trust_realm }
	content = """ \n[libdefaults]\n  renew_lifetime = 7d\n  forwardable = true\n  default_realm = {{realm}}\n  ticket_lifetime = 24h\n  dns_lookup_realm = false\n  dns_lookup_kdc = false\n  default_ccache_name = /tmp/krb5cc_%{uid}\n  #default_tgs_enctypes = {{encryption_types}}\n  #default_tkt_enctypes = {{encryption_types}}\n{% if domains %}\n[domain_realm]\n{%- for domain in domains.split(',') %}\n  {{domain|trim()}} = {{realm}}\n{%- endfor %}\n{% endif %}\n[logging]\n  default = FILE:/var/log/krb5kdc.log\n  admin_server = FILE:/var/log/kadmind.log\n  kdc = FILE:/var/log/krb5kdc.log\n\n[realms]\n  {{realm}} = {\n{%- if kdc_hosts > 0 -%}\n{%- set kdc_host_list = kdc_hosts.split(',')  -%}\n{%- if kdc_host_list and kdc_host_list|length > 0 %}\n    admin_server = {{admin_server_host|default(kdc_host_list[0]|trim(), True)}}\n{%- if kdc_host_list -%}\n{% for kdc_host in kdc_host_list %}\n    kdc = {{kdc_host|trim()}}\n{%- endfor -%}\n{% endif %}\n{%- endif %}\n{%- endif %}\n  }\n\n{# Append additional realm declarations below #}\n  """
	content_append = trust_realm + " = {\nadmin_server = " + trust_kdc + "\nkdc = " + trust_kdc + "\n}\n"
	snip["krb5-conf"]["properties"]["contents"] = content + content_append
b["configurations"].append ( snip )
b["Blueprints"]["stack_version"] = version_short

jsonFile = open( blueprint_target, "w+" )
jsonFile.write(json.dumps( b, sort_keys=True, indent=4, separators=(',', ': ') ) )
jsonFile.close()

