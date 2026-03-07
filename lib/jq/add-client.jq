# add-client.jq — add one client and one shortId. Expects --arg uuid, --arg sid, --arg email.
.inbounds[0].settings.clients += [{
  id: $uuid,
  flow: "xtls-rprx-vision",
  email: $email
}] |
.inbounds[0].streamSettings.realitySettings.shortIds += [$sid]
