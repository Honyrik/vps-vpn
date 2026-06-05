--[[
  Статус сетевых интерфейсов для OpenResty (Linux и FreeBSD).

  ВАЖНО: stock nginx (pkg install nginx) НЕ поддерживает content_by_lua_file.
  На FreeBSD нужен OpenResty:
    pkg install openresty
    service openresty enable
    service openresty start
  Конфиг: /usr/local/etc/openresty/nginx.conf
  Бинарь: /usr/local/openresty/nginx/sbin/nginx

  Без OpenResty используйте interfaces_status.py + fcgiwrap:
    см. nginx-interfaces-freebsd.conf.example

  Пример OpenResty:
    location /api/interfaces {
        allow 127.0.0.1;
        allow 10.0.0.0/8;
        deny all;
        content_by_lua_file /opt/router/scripts/interfaces_status.lua;
    }

  Формат ответа: JSON (по умолчанию) или text (?format=text).
  cjson опционален — без него JSON собирается вручную.
]]

local cjson_ok, cjson = pcall(require, "cjson.safe")
if not cjson_ok then
    cjson = nil
end

local SKIP_LOOPBACK = true

local function trim(s)
    if not s then
        return nil
    end
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function read_file(path)
    local f = io.open(path, "r")
    if not f then
        return nil
    end
    local data = f:read("*a")
    f:close()
    return trim(data)
end

local function run_cmd(cmd)
    local f = io.popen(cmd .. " 2>/dev/null")
    if not f then
        return nil
    end
    local out = f:read("*a")
    f:close()
    if out == "" then
        return nil
    end
    return out
end

local function detect_os()
    local uname = trim(run_cmd("uname -s"))
    if uname == "FreeBSD" then
        return "freebsd"
    end
    if uname == "Linux" then
        return "linux"
    end
    if read_file("/proc/net/dev") then
        return "linux"
    end
    return "freebsd"
end

local OS = detect_os()

local INET_PING_HOSTS = { "1.1.1.1", "8.8.8.8", "77.88.8.8", "9.9.9.9", "77.88.8.1" }
local INET_PING_TIMEOUT = 2

local function ping_host(host)
    local timeout = INET_PING_TIMEOUT
    local cmd
    if OS == "freebsd" then
        cmd = string.format("ping -c 1 -t %d %s", timeout, host)
    else
        cmd = string.format("ping -c 1 -W %d %s", timeout, host)
    end
    local rc = os.execute(cmd .. " >/dev/null 2>&1")
    return rc == 0 or rc == true
end

local function check_inet()
    for _, host in ipairs(INET_PING_HOSTS) do
        if ping_host(host) then
            return true
        end
    end
    return false
end

local function is_loopback(name)
    return name == "lo" or name:match("^lo%d+$") ~= nil
end

local function flag_set(flags, mask)
    local n = tonumber(flags)
    if not n then
        return false
    end
    return bit.band(n, mask) ~= 0
end

local function ipv4_dotted_to_prefix(dotted)
    local n = 0
    for octet in dotted:gmatch("%d+") do
        n = bit.lshift(n, 8) + tonumber(octet)
    end
    local bits = 0
    while n > 0 do
        if bit.band(n, 1) == 1 then
            bits = bits + 1
        end
        n = bit.rshift(n, 1)
    end
    return bits
end

local function netmask_to_prefix(mask)
    if not mask then
        return 0
    end
    if mask:match("^0[xX]") then
        local n = tonumber(mask)
        if not n then
            return 0
        end
        local bits = 0
        while n > 0 do
            if bit.band(n, 1) == 1 then
                bits = bits + 1
            end
            n = bit.rshift(n, 1)
        end
        return bits
    end
    if mask:match("%.") then
        return ipv4_dotted_to_prefix(mask)
    end
    return tonumber(mask) or 0
end

-- ---------------------------------------------------------------------------
-- Linux
-- ---------------------------------------------------------------------------

local function linux_list_interfaces()
    local names = {}
    local seen = {}

    local out = run_cmd("ls -1 /sys/class/net")
    if out then
        for line in out:gmatch("[^\r\n]+") do
            local name = trim(line)
            if name and name ~= "" and not seen[name] then
                seen[name] = true
                names[#names + 1] = name
            end
        end
    end

    table.sort(names)
    return names
end

local function linux_parse_proc_net_dev()
    local stats = {}
    local f = io.open("/proc/net/dev", "r")
    if not f then
        return stats
    end

    local n = 0
    for line in f:lines() do
        n = n + 1
        if n > 2 then
            local iface, rest = line:match("^%s*([^:%s]+):%s*(.+)$")
            if iface and rest then
                local fields = {}
                for part in rest:gmatch("%S+") do
                    fields[#fields + 1] = part
                end
                if #fields >= 16 then
                    stats[iface] = {
                        rx_bytes = tonumber(fields[1]) or 0,
                        rx_packets = tonumber(fields[2]) or 0,
                        rx_errors = tonumber(fields[3]) or 0,
                        rx_dropped = tonumber(fields[4]) or 0,
                        tx_bytes = tonumber(fields[9]) or 0,
                        tx_packets = tonumber(fields[10]) or 0,
                        tx_errors = tonumber(fields[11]) or 0,
                        tx_dropped = tonumber(fields[12]) or 0,
                    }
                end
            end
        end
    end

    f:close()
    return stats
end

local function linux_load_addresses()
    local by_iface = {}

    if cjson then
        local json = run_cmd("ip -json addr show")
        if json then
            local data = cjson.decode(json)
            if data then
                for _, link in ipairs(data) do
                    local name = link.ifname
                    if name then
                        by_iface[name] = { ipv4 = {}, ipv6 = {} }
                        for _, info in ipairs(link.addr_info or {}) do
                            local entry = {
                                address = info["local"],
                                prefix = info.prefixlen,
                                scope = info.scope,
                                family = info.family,
                            }
                            if info.family == "inet" then
                                by_iface[name].ipv4[#by_iface[name].ipv4 + 1] = entry
                            elseif info.family == "inet6" then
                                by_iface[name].ipv6[#by_iface[name].ipv6 + 1] = entry
                            end
                        end
                    end
                end
                return by_iface
            end
        end
    end

    local text = run_cmd("ip -o addr show")
    if not text then
        return by_iface
    end

    for line in text:gmatch("[^\r\n]+") do
        local family, name, addr, prefix = line:match("^%d+%:%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)")
        if family and name and addr then
            if not by_iface[name] then
                by_iface[name] = { ipv4 = {}, ipv6 = {} }
            end
            local entry = {
                address = addr,
                prefix = tonumber(prefix) or 0,
                scope = nil,
                family = family,
            }
            if family == "inet" then
                by_iface[name].ipv4[#by_iface[name].ipv4 + 1] = entry
            elseif family == "inet6" then
                by_iface[name].ipv6[#by_iface[name].ipv6 + 1] = entry
            end
        end
    end

    return by_iface
end

local function linux_collect_interface(name, addrs, stats)
    local operstate = read_file("/sys/class/net/" .. name .. "/operstate") or "unknown"
    local carrier = read_file("/sys/class/net/" .. name .. "/carrier")
    local mac = read_file("/sys/class/net/" .. name .. "/address")
    local mtu = tonumber(read_file("/sys/class/net/" .. name .. "/mtu"))
    local flags_raw = read_file("/sys/class/net/" .. name .. "/flags")
    local ifindex = tonumber(read_file("/sys/class/net/" .. name .. "/ifindex"))

    local addr = addrs[name] or { ipv4 = {}, ipv6 = {} }
    local st = stats[name] or {}

    return {
        name = name,
        ifindex = ifindex,
        up = flag_set(flags_raw, 1),
        operstate = operstate,
        carrier = carrier == "1",
        mac = mac,
        mtu = mtu,
        ipv4 = addr.ipv4,
        ipv6 = addr.ipv6,
        stats = st,
    }
end

local function linux_collect_all()
    local addrs = linux_load_addresses()
    local stats = linux_parse_proc_net_dev()
    local result = {}

    for _, name in ipairs(linux_list_interfaces()) do
        if not (SKIP_LOOPBACK and is_loopback(name)) then
            result[#result + 1] = linux_collect_interface(name, addrs, stats)
        end
    end

    return result
end

-- ---------------------------------------------------------------------------
-- FreeBSD
-- ---------------------------------------------------------------------------

local function freebsd_list_interfaces()
    local names = {}
    local seen = {}

    local out = run_cmd("ifconfig -l")
    if out then
        for name in out:gmatch("%S+") do
            if not seen[name] then
                seen[name] = true
                names[#names + 1] = name
            end
        end
    end

    if #names == 0 then
        out = run_cmd("ifconfig -a")
        if out then
            for line in out:gmatch("[^\r\n]+") do
                local name = line:match("^(%S+):")
                if name and not seen[name] then
                    seen[name] = true
                    names[#names + 1] = name
                end
            end
        end
    end

    table.sort(names)
    return names
end

local function freebsd_parse_netstat_stats()
    local stats = {}
    local out = run_cmd("netstat -I -b -n")
    if not out then
        return stats
    end

    local past_header = false
    for line in out:gmatch("[^\r\n]+") do
        if line:match("^Name") then
            past_header = true
        elseif past_header and line:match("<Link#") then
            local name, ipkts, ierrs, idrop, ibytes, opkts, oerrs, obytes = line:match(
                "^(%S+)%s+%d+%s+<Link#[^>]+>%s+%S+%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)"
            )
            if name then
                stats[name] = {
                    rx_bytes = tonumber(ibytes) or 0,
                    rx_packets = tonumber(ipkts) or 0,
                    rx_errors = tonumber(ierrs) or 0,
                    rx_dropped = tonumber(idrop) or 0,
                    tx_bytes = tonumber(obytes) or 0,
                    tx_packets = tonumber(opkts) or 0,
                    tx_errors = tonumber(oerrs) or 0,
                    tx_dropped = 0,
                }
            end
        end
    end

    return stats
end

local function freebsd_parse_ifconfig()
    local by_name = {}
    local out = run_cmd("ifconfig -a")
    if not out then
        return by_name
    end

    local cur = nil

    local function ensure(name)
        if not by_name[name] then
            by_name[name] = {
                name = name,
                ifindex = nil,
                up = false,
                operstate = "unknown",
                carrier = false,
                mac = nil,
                mtu = nil,
                ipv4 = {},
                ipv6 = {},
                stats = {},
            }
        end
        return by_name[name]
    end

    for line in out:gmatch("[^\r\n]+") do
        local name, rest = line:match("^(%S+):%s*(.*)$")
        if name then
            cur = ensure(name)
            local flags = rest:match("<([^>]+)>")
            cur.up = flags and flags:find("UP", 1, true) ~= nil or false
            local running = flags and flags:find("RUNNING", 1, true) ~= nil or false
            cur.mtu = tonumber(rest:match("mtu (%d+)"))
            cur.operstate = running and "up" or "down"
            cur.carrier = running
        elseif cur and line:match("^[%s\t]") then
            local ether = line:match("ether (%S+)")
            if ether then
                cur.mac = ether
            end

            local status = line:match("status:%s+(%S+)")
            if status then
                cur.carrier = status == "active"
                cur.operstate = (status == "active") and "up" or "down"
            end

            local inet, mask = line:match("inet%s+(%S+)%s+[%S%s]*netmask%s+(%S+)")
            if inet and mask then
                cur.ipv4[#cur.ipv4 + 1] = {
                    address = inet,
                    prefix = netmask_to_prefix(mask),
                    scope = nil,
                    family = "inet",
                }
            end

            local inet_cidr, pfx = line:match("inet%s+(%S+)/(%d+)")
            if inet_cidr and pfx and not inet then
                cur.ipv4[#cur.ipv4 + 1] = {
                    address = inet_cidr,
                    prefix = tonumber(pfx) or 0,
                    scope = nil,
                    family = "inet",
                }
            end

            local inet6, pfx6 = line:match("inet6%s+(%S+)%s+prefixlen%s+(%d+)")
            if inet6 and pfx6 then
                local addr6 = inet6:gsub("%%.+$", "")
                cur.ipv6[#cur.ipv6 + 1] = {
                    address = addr6,
                    prefix = tonumber(pfx6) or 0,
                    scope = nil,
                    family = "inet6",
                }
            end

            local inet6_cidr, pfx6b = line:match("inet6%s+(%S+)/(%d+)")
            if inet6_cidr and pfx6b and not inet6 then
                local addr6 = inet6_cidr:gsub("%%.+$", "")
                cur.ipv6[#cur.ipv6 + 1] = {
                    address = addr6,
                    prefix = tonumber(pfx6b) or 0,
                    scope = nil,
                    family = "inet6",
                }
            end
        end
    end

    return by_name
end

local function freebsd_collect_all()
    local stats = freebsd_parse_netstat_stats()
    local by_name = freebsd_parse_ifconfig()
    local result = {}

    for _, name in ipairs(freebsd_list_interfaces()) do
        if not (SKIP_LOOPBACK and is_loopback(name)) then
            local iface = by_name[name] or {
                name = name,
                ifindex = nil,
                up = false,
                operstate = "unknown",
                carrier = false,
                mac = nil,
                mtu = nil,
                ipv4 = {},
                ipv6 = {},
                stats = {},
            }
            iface.stats = stats[name] or {}
            result[#result + 1] = iface
        end
    end

    return result
end

-- ---------------------------------------------------------------------------
-- Response
-- ---------------------------------------------------------------------------

local function collect_all()
    local interfaces
    if OS == "freebsd" then
        interfaces = freebsd_collect_all()
    else
        interfaces = linux_collect_all()
    end

    return {
        platform = OS,
        hostname = trim(run_cmd("hostname -s")) or (ngx and ngx.var and ngx.var.hostname) or nil,
        timestamp = ngx and ngx.time and ngx.time() or os.time(),
        inet = check_inet(),
        interfaces = interfaces,
    }
end

local function format_text(payload)
    local lines = {}
    lines[#lines + 1] = string.format(
        "platform=%s host=%s ts=%s inet=%s interfaces=%d",
        payload.platform or "?",
        payload.hostname or "?",
        tostring(payload.timestamp),
        payload.inet and "yes" or "no",
        #payload.interfaces
    )

    for _, iface in ipairs(payload.interfaces) do
        local ips = {}
        for _, v4 in ipairs(iface.ipv4 or {}) do
            ips[#ips + 1] = v4.address .. "/" .. tostring(v4.prefix)
        end
        for _, v6 in ipairs(iface.ipv6 or {}) do
            ips[#ips + 1] = v6.address .. "/" .. tostring(v6.prefix)
        end

        lines[#lines + 1] = string.format(
            "%s up=%s operstate=%s carrier=%s mtu=%s mac=%s rx=%s tx=%s ips=%s",
            iface.name,
            iface.up and "yes" or "no",
            iface.operstate,
            iface.carrier and "yes" or "no",
            tostring(iface.mtu or "-"),
            iface.mac or "-",
            tostring((iface.stats or {}).rx_bytes or 0),
            tostring((iface.stats or {}).tx_bytes or 0),
            (#ips > 0) and table.concat(ips, ",") or "-"
        )
    end

    return table.concat(lines, "\n") .. "\n"
end

local function json_escape(s)
    s = tostring(s)
    s = s:gsub("\\", "\\\\")
    s = s:gsub('"', '\\"')
    s = s:gsub("\n", "\\n")
    s = s:gsub("\r", "\\r")
    s = s:gsub("\t", "\\t")
    return s
end

local encode_json_value

local function is_json_array(t)
    local count = 0
    local max = 0
    for k, _ in pairs(t) do
        if type(k) ~= "number" or k < 1 or k ~= math.floor(k) then
            return false
        end
        count = count + 1
        if k > max then
            max = k
        end
    end
    return max == count
end

local function encode_json(obj)
    if is_json_array(obj) then
        local parts = {}
        for i = 1, #obj do
            parts[#parts + 1] = encode_json_value(obj[i])
        end
        return "[" .. table.concat(parts, ",") .. "]"
    end

    local parts = {}
    for k, v in pairs(obj) do
        parts[#parts + 1] = '"' .. json_escape(k) .. '":' .. encode_json_value(v)
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

encode_json_value = function(v)
    local t = type(v)
    if v == nil then
        return "null"
    end
    if t == "boolean" then
        return v and "true" or "false"
    end
    if t == "number" then
        return tostring(v)
    end
    if t == "string" then
        return '"' .. json_escape(v) .. '"'
    end
    if t == "table" then
        return encode_json(v)
    end
    return "null"
end

local function format_json(payload)
    if cjson then
        return cjson.encode(payload)
    end
    return encode_json(payload)
end

local function respond()
    local payload = collect_all()
    local fmt = ngx.var.arg_format or "json"

    if fmt == "text" then
        ngx.header["Content-Type"] = "text/plain; charset=utf-8"
        ngx.say(format_text(payload))
        return
    end

    ngx.header["Content-Type"] = "application/json; charset=utf-8"
    ngx.say(format_json(payload))
end

respond()
