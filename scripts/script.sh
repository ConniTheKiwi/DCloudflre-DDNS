#!/bin/sh
# cf-ddns.sh - https://github.com/gstuartj/cf-ddns.sh/
# A minimal, portable DDNS client for CloudFlare API v4 meant for use w/ cron
# Requires: curl (w/ HTTPS support), grep, awk

helptext=`cat << ENDHELP
Usage: DUpdateDNS.sh [OPTION] -e=EMAIL -a=APIKEY -y=ZONEID -q=RECORDID
A minimal, portable DDNS client for CloudFlare
Required
  -e=, --email=		CloudFlare account email
  -a=, --apikey=	CloudFlare account API key
  -y=, --zoneid=	CloudFlare zone ID
  -q=, --recordid=	CloudFlare record ID
Options
  -w=, --wan=		Manually specify WAN IP address, skip detection
  -h, --help		Print this message and exit
ENDHELP`
#Configuration - these options can be hard-coded or passed as parameters
###############
# CF credentials - required
cf_email=''
cf_api_key=''
# Zone name - can be blank if zone_id is set
zone_name=''
# Zone ID - if blank, will be looked up using zone_name
zone_id='' # If blank, will be looked up
# DNS record name  (e.g. domain.tld or subdomain.domain.tld)
# - can be blank if record_id is set
record_name=''
# DNS record ID - if blank, will be looked up using record_name
record_id=''
###############
#The defaults below should be fine.
# Command to run for curl requests. If using alternate version, specify path.
curl_command='curl'
# WAN address - DNS A record will be updated to point to this address
WAN_addr=''
# Internal hostnames for WAN address lookup
# - (optional, will fallback to external source)
internal_wan_hostnames='wan wan-ip wan1-ip'
# External WAN service. Do not include protocol. HTTPS will be tried first.
# External WAN service. Ensure only IPv4 addresses are returned as the script does not currently support AAAA records.
# URL should return ONLY the IP address as a response
external_WAN_query='https://api.ipify.org'
#external_WAN_query='https://ipv4.icanhazip.com' 
#external_WAN_query='https://ifconfig.io/ip'
# Where to store the address from our last update. /tmp/ is fine.
storage_dir='/tmp/'
# Force update if address hasn't changed?
force=false
# CloudFlare API (v4) URL
cf_api_url='https://api.cloudflare.com/client/v4/'
#END CONFIGURATION
#Functions
###############
validate_ip_addr () {
    if [ -z $1 ]; then return 1; fi
    if [ "${1}" != "${1#*[0-9].[0-9]}" ] && [ "${1}" != "${1#*:[0-9a-fA-F]}" ]; then
        return 1
    fi
    return 0
}
lookup_WAN_addr () {
    local WAN_lookup
    # Go through internal WAN hostnames and get WAN IP, if possible
    for i in $internal_wan_hostnames; do
        WAN_lookup=`nslookup ${i} | awk '/^Address: / { print $2 }'`
        if [ -n $WAN_lookup ]; then
            continue
        fi
    done
    # If internal WAN hostnames didn't return an IP, fallback to external service
    if [ -z $WAN_lookup ]; then
        WAN_lookup=`${curl_command} -s ${external_WAN_query}`
    fi
    if [ ! $WAN_lookup ]; then
        echo "Couldn't determine WAN IP. Please specify as an argument."
        return 1
    fi
    if validate_ip_addr $WAN_lookup; then
        echo "${WAN_lookup}"
        return 0
    fi
    return 1
}
set_WAN_addr () {
    if [ ! -z $1 ]; then
        if validate_ip_addr $1; then
	    WAN_addr="${1}"
            return 0
        else
            echo "WAN IP is invalid."
	    exit 1
        fi
    else
        set_WAN_addr `lookup_WAN_addr`
	return 0
    fi
    return 1
}
lookup_zone_id () {
    local zones
    local zname
    if [ ! -z $1 ]; then
        zname="${1}"
    else
        zname=$zone_name
    fi
    if [ -z $zname ]; then
        echo "No zone name provided."
        exit 1
    fi
    zones=`${curl_command} -s -X GET "${cf_api_url}/zones?name=${zname}" -H "X-Auth-Email: ${cf_email}" -H "X-Auth-Key: ${cf_api_key}" -H "Content-Type: application/json"`
    if [ ! "${zones}" ]; then
        echo "Request to API failed during zone lookup."
        exit 1
    fi
    if [ -n "${zones##*\"success\":true*}" ]; then
        echo "Failed to lookup zone ID. Check zone name or specify an ID."
        echo "${zones}"
        exit 1
    fi
    echo "${zones}" | grep -Po '(?<="id":")[^"]*' | head -1
    return 0
}
set_zone_id () {
    if [ ! -z $1 ]; then
        if [ -n "${1##*\.*}"]; then
	    zone_id=`lookup_zone_id "${1}"`
            return 0
        else
            zone_id="${1}"
	    return 0
        fi
    elif [ -n $zone_name ]; then
        set_zone_id $zone_name
	return 0
    fi
    return 1
}	
do_record_update () {
    # Perform record update
    api_dns_update=`${curl_command} -s -X PUT "${cf_api_url}/zones/${zone_id}/dns_records/${record_id}" -H "X-Auth-Email: ${cf_email}" -H "X-Auth-Key: ${cf_api_key}" -H "Content-Type: application/json" --data "{\"id\":\"${zone_id}\",\"type\":\"A\",\"name\":\"${record_name}\",\"content\":\"${WAN_addr}\"}"`
    if [ ! "${api_dns_update}" ]; then
        echo "There was a problem communicating with the API server. Check your connectivity and parameters."
        echo "${api_dns_update}"
        exit 1
    fi
    if [ -n "${api_dns_update##*\"success\":true*}" ]; then
        echo "Record update failed."
        echo "${api_dns_update}"
        exit 1
    fi
    # Save WAN address to file for comparison on subsequent runs
    echo "${WAN_addr}" > $prev_addr_file
    return 0
}
#End functions
#Main
###############
# Remove the last trailing slash from storage_dir and cf_api_url
storage_dir=${storage_dir%/}
cf_api_url=${cf_api_url%/}
# Show help and exit if no option was passed in the command line
if [ -z "${1}" ]; then
    echo "${helptext}"
    exit 0
fi
# Get options and arguments from the command line
for key in "$@"; do
    case $key in
    -y=*|--zoneid=*)
        set_zone_id "${key#*=}"
        shift
    ;;
    -q=*|--recordid=*)
        record_id="${key#*=}"
        shift
    ;;
    -e=*|--email=*)
        cf_email="${key#*=}"
        shift
    ;;
    -a=*|--apikey=*)
        cf_api_key="${key#*=}"
        shift
    ;;
    -w=*|--wan=*)
        set_WAN_addr "${key#*=}"
        shift
    ;;
    -h|--help)
        echo "${helptext}"
        exit 0
    ;;
    -f|--force)
        force=true
        shift
    ;;
    *)
        echo "Unknown option '${key}'"
        exit 1
    ;;
    esac
done
# Check if curl supports https
curl_https_check=`${curl_command} --version`
if [ -n "${curl_https_check##*https*}" ]; then
    echo "Your version of curl doesn't support HTTPS. Exiting."
    exit 1
fi

# If address from previous update was saved, load it
prev_addr=''
prev_addr_file="${storage_dir}/cf-ddns_${zone_id}_${record_id}.addr"
if [ -f $prev_addr_file ]; then
    prev_addr=`cat ${prev_addr_file}`
fi
if [ -z $WAN_addr ]; then 
    set_WAN_addr; 
fi

# No change. Stop unless force is specified.
if [ -n $prev_addr ] && [ "${prev_addr}" = "${WAN_addr}" ] && [ $force = false ]; then
    echo 'WAN IP appears unchanged. You can force an update with -f.'
    exit 0
fi

do_record_update
echo "Record updated."
DWebhook "Updated DDNS with ip $WAN_addr"
exit 0
