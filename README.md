# Cloudflare-DNS-Updater
 
# # Description
This project is a cloudflare DDNS client that will update your cloudflare DNS Settings automatically
this project is based off the code from 
https://github.com/gstuartj/cf-ddns.sh
and i have taken a few changes from some of the pull requests as well to bring the script up to date

i have stripped alot of functionality from the script to suit the use case of this recoded application

this project depends on one of my other repos linked below in # Prerequisites

# # Install
Download to your system and create a cron job to run the script with your parameters on an interval.

# # Prerequisites
- POSIX-ish environment (Linux, OS X, BSD, etc.)
- curl (requires HTTPS support)
- https://github.com/ConniTheKiwi/Linux-Discord-Intergration

# # Usage
./script.sh --email= --apikey= --zoneid= --recordid=
