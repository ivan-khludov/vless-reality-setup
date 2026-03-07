# remove-client.jq — remove client and shortId at 0-based index $i. Expects --argjson i <index>.
.inbounds[0] |= (
  .settings.clients = (.settings.clients | .[0:$i] + .[$i+1:]) |
  .streamSettings.realitySettings.shortIds = (.streamSettings.realitySettings.shortIds | .[0:$i] + .[$i+1:])
)
