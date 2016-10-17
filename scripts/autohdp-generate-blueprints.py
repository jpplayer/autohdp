#!/usr/bin/python

import sys
import json

blueprint_source = sys.argv[1]
blueprint_target = sys.argv[2]
realm = sys.argv[3]
kdc = sys.argv[4]
version_short = sys.argv[5]


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

snip = json.loads( krb_snip_conf )
domain = kdc [ kdc.index(".") : ]
snip["krb5-conf"]["properties"]["domains"] = "*" + domain + " = " + realm 
b["configurations"].append ( snip )

b["Blueprints"]["security"] = { "type" :"KERBEROS" }

b["Blueprints"]["stack_version"] = version_short

jsonFile = open( blueprint_target, "w+" )
jsonFile.write(json.dumps( b, sort_keys=True, indent=4, separators=(',', ': ') ) )
jsonFile.close()

