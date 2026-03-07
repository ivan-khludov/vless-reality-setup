# change-sni.jq — set serverNames[0] and dest. Expects --arg sni, --arg dest.
.inbounds[0].streamSettings.realitySettings |= (
  .serverNames[0] = $sni | .dest = $dest
)
