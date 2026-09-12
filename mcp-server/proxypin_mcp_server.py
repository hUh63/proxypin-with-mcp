#!/usr/bin/env python3
"""ProxyPin MCP Server - 整合版"""
import os
import json
import requests
from typing import Dict, Any, Optional, List
from fastmcp import FastMCP

# ProxyPin HTTP API配置
PROXYPIN_HOST = os.getenv("PROXYPIN_HOST", "127.0.0.1")
PROXYPIN_PORT = int(os.getenv("PROXYPIN_PORT", "9010"))
BASE_URL = f"http://{PROXYPIN_HOST}:{PROXYPIN_PORT}"
MESSAGES_URL = f"{BASE_URL}/messages"

# 创建Session，不使用系统代理
session = requests.Session()
session.trust_env = False
request_id_counter = 1

def call_proxypin_tool(tool_name: str, arguments: Optional[Dict[str, Any]] = None, timeout: int = 30) -> Any:
    """调用ProxyPin的MCP工具
    
    参数:
    - tool_name: 工具名称
    - arguments: 工具参数
    - timeout: HTTP请求超时时间(秒)
    """
    global request_id_counter
    
    if arguments is None:
        arguments = {}
    
    payload = {
        "jsonrpc": "2.0",
        "id": request_id_counter,
        "method": "tools/call",
        "params": {
            "name": tool_name,
            "arguments": arguments
        }
    }
    request_id_counter += 1
    
    try:
        response = session.post(MESSAGES_URL, json=payload, timeout=timeout)
        response.raise_for_status()
        
        # 处理 202 Accepted (通知类消息无响应体)
        if response.status_code == 202:
            return {}
        
        result = response.json()
        
        if "error" in result:
            raise Exception(f"MCP Error: {result['error']}")
        
        # 提取实际内容
        content = result.get("result", {}).get("content", [])
        if content:
            text = content[0].get("text", "{}")
            return json.loads(text)
        return {}
    except requests.exceptions.RequestException as e:
        raise Exception(f"ProxyPin连接失败: {e}")

mcp = FastMCP("ProxyPin")

@mcp.tool()
def search_requests(
    query: str = None, 
    method: str = None, 
    status_code: str = None,
    domain: str = None,
    header_search: str = None,
    request_body_search: str = None,
    response_body_search: str = None,
    min_duration: int = None,
    max_duration: int = None,
    limit: int = 20
):
    """高级搜索HTTP请求
    
    支持多种过滤条件：
    - query: URL关键词
    - method: HTTP方法(GET/POST等)
    - status_code: 状态码("200"或"2xx"范围)
    - domain: 域名过滤
    - header_search: 搜索请求/响应header
    - request_body_search: 搜索请求body(限1MB)
    - response_body_search: 搜索响应body(限1MB)
    - min_duration/max_duration: 响应时间范围(毫秒)
    """
    args = {"limit": limit}
    if query:
        args["query"] = query
    if method:
        args["method"] = method
    if status_code:
        args["status_code"] = status_code
    if domain:
        args["domain"] = domain
    if header_search:
        args["header_search"] = header_search
    if request_body_search:
        args["request_body_search"] = request_body_search
    if response_body_search:
        args["response_body_search"] = response_body_search
    if min_duration is not None:
        args["min_duration"] = min_duration
    if max_duration is not None:
        args["max_duration"] = max_duration
    return call_proxypin_tool("search_requests", args)

@mcp.tool()
def get_request_details(request_id: str):
    """获取请求详情"""
    return call_proxypin_tool("get_request_details", {"request_id": request_id})

@mcp.tool()
def replay_request(request_id: str):
    """重放请求"""
    return call_proxypin_tool("replay_request", {"request_id": request_id})

@mcp.tool()
def generate_code(request_id: str, language: str = "python"):
    """生成代码(python/js/curl)"""
    return call_proxypin_tool("generate_code", {"request_id": request_id, "language": language})

@mcp.tool()
def get_curl(request_id: str):
    """生成cURL命令"""
    return call_proxypin_tool("get_curl", {"request_id": request_id})

@mcp.tool()
def block_url(url_pattern: str, block_type: str = "blockRequest"):
    """屏蔽URL"""
    return call_proxypin_tool("block_url", {"url_pattern": url_pattern, "block_type": block_type})

@mcp.tool()
def add_response_rewrite(url_pattern: str, rewrite_type: str, value: str, key: str = None):
    """添加响应重写规则"""
    args = {"url_pattern": url_pattern, "rewrite_type": rewrite_type, "value": value}
    if key:
        args["key"] = key
    return call_proxypin_tool("add_response_rewrite", args)

@mcp.tool()
def add_request_rewrite(url_pattern: str, rewrite_type: str, key: str, value: str):
    """添加请求重写规则"""
    return call_proxypin_tool("add_request_rewrite", {
        "url_pattern": url_pattern,
        "rewrite_type": rewrite_type,
        "key": key,
        "value": value
    })

@mcp.tool()
def update_script(name: str, url_pattern: str, script_content: str):
    """创建或更新JavaScript脚本"""
    return call_proxypin_tool("update_script", {
        "name": name,
        "url_pattern": url_pattern,
        "script_content": script_content
    })

@mcp.tool()
def get_scripts():
    """获取所有脚本"""
    return call_proxypin_tool("get_scripts")

@mcp.tool()
def set_config(system_proxy: bool = None, ssl_capture: bool = None):
    """设置ProxyPin配置"""
    args = {}
    if system_proxy is not None:
        args["system_proxy"] = system_proxy
    if ssl_capture is not None:
        args["ssl_capture"] = ssl_capture
    return call_proxypin_tool("set_config", args)

@mcp.tool()
def add_host_mapping(domain: str, ip: str):
    """添加Hosts映射"""
    return call_proxypin_tool("add_host_mapping", {"domain": domain, "ip": ip})

@mcp.tool()
def get_proxy_status():
    """获取代理状态"""
    return call_proxypin_tool("get_proxy_status")

@mcp.tool()
def export_har(limit: int = 100, request_ids: List[str] = None):
    """导出HAR
    
    参数:
    - limit: 最大导出请求数(默认100)
    - request_ids: 指定请求ID列表导出(可选)
    """
    args = {"limit": limit}
    if request_ids:
        args["request_ids"] = request_ids
    return call_proxypin_tool("export_har", args)

@mcp.tool()
def import_har(har_content: str):
    """导入HAR文件到ProxyPin
    
    参数:
    - har_content: HAR JSON字符串
    """
    return call_proxypin_tool("import_har", {"har_content": har_content})

@mcp.tool()
def start_proxy(port: int = 9099):
    """启动代理服务器
    
    参数:
    - port: 代理端口(默认9099)
    """
    return call_proxypin_tool("start_proxy", {"port": port})

@mcp.tool()
def stop_proxy():
    """停止代理服务器"""
    return call_proxypin_tool("stop_proxy")

@mcp.tool()
def get_recent_requests(limit: int = 20, url_filter: str = None, method: str = None):
    """获取最近的请求列表(Legacy)
    
    注意: 建议使用 search_requests 替代此方法
    """
    args = {"limit": limit}
    if url_filter:
        args["url_filter"] = url_filter
    if method:
        args["method"] = method
    return call_proxypin_tool("get_recent_requests", args)

@mcp.tool()
def clear_requests():
    """清空所有捕获的请求"""
    return call_proxypin_tool("clear_requests")

@mcp.tool()
def get_statistics():
    """获取请求统计信息
    
    返回：
    - total: 总请求数
    - methods: HTTP方法分布
    - statusCodes: 状态码分布(2xx/3xx/4xx/5xx)
    - domains: 域名分布
    - totalSize: 总数据大小
    - averageDuration: 平均响应时间
    - errorCount: 错误请求数
    """
    return call_proxypin_tool("get_statistics")

@mcp.tool()
def compare_requests(request_id_1: str, request_id_2: str):
    """对比两个请求的差异
    
    返回详细对比信息：
    - request_header_diff: 请求Header差异
    - response_header_diff: 响应Header差异
    - request_body_diff: 请求Body差异(支持JSON diff)
    - response_body_diff: 响应Body差异(支持JSON diff)
    - duration_diff: 响应时间差异
    """
    return call_proxypin_tool("compare_requests", {
        "request_id_1": request_id_1,
        "request_id_2": request_id_2
    })

@mcp.tool()
def find_similar_requests(request_id: str, limit: int = 10):
    """查找与指定请求相似的其他请求
    
    相似条件：相同域名、路径和HTTP方法
    """
    return call_proxypin_tool("find_similar_requests", {
        "request_id": request_id,
        "limit": limit
    })

@mcp.tool()
def extract_api_endpoints(domain_filter: str = None):
    """提取并分组所有API端点
    
    返回：
    - endpoints: 端点列表(包含method/domain/path/count/status_codes)
    - total_unique: 唯一端点总数
    
    用途：自动生成API文档、了解系统API结构
    """
    args = {}
    if domain_filter:
        args["domain_filter"] = domain_filter
    return call_proxypin_tool("extract_api_endpoints", args)

# ==================== 设备控制工具 (仅Android) ====================

@mcp.tool()
def get_device_info():
    """获取Android设备信息
    
    返回：型号、品牌、Android版本、WiFi IP、Root/无障碍状态
    """
    return call_proxypin_tool("get_device_info")

@mcp.tool()
def get_current_activity():
    """获取当前前台Activity/包名"""
    return call_proxypin_tool("get_current_activity")

@mcp.tool()
def dump_ui(clickable_only: bool = False, package_filter: str = None):
    """导出当前Android UI层级为JSON
    
    参数:
    - clickable_only: 仅返回可点击元素(默认False)
    - package_filter: 按包名过滤
    """
    args = {"clickable_only": clickable_only}
    if package_filter:
        args["package_filter"] = package_filter
    return call_proxypin_tool("dump_ui", args)

@mcp.tool()
def tap_screen(x: int, y: int):
    """在指定坐标点击屏幕
    
    参数:
    - x: X坐标
    - y: Y坐标
    """
    return call_proxypin_tool("tap_screen", {"x": x, "y": y})

@mcp.tool()
def long_press(x: int, y: int, duration: int = 50):
    """在指定坐标长按
    
    参数:
    - x: X坐标
    - y: Y坐标
    - duration: 按压时长(毫秒, 默认50)
    """
    return call_proxypin_tool("long_press", {"x": x, "y": y, "duration": duration})

@mcp.tool()
def swipe_screen(x1: int, y1: int, x2: int, y2: int, duration: int = 300):
    """执行滑动手势
    
    参数:
    - x1, y1: 起点坐标
    - x2, y2: 终点坐标
    - duration: 滑动时长(毫秒, 默认300)
    """
    return call_proxypin_tool("swipe_screen", {
        "x1": x1, "y1": y1, "x2": x2, "y2": y2, "duration": duration
    })

@mcp.tool()
def key_event(keycode: int):
    """发送按键事件
    
    常用键码: 3=HOME, 4=BACK, 26=POWER, 82=MENU, 187=RECENTS
    """
    return call_proxypin_tool("key_event", {"keycode": keycode})

@mcp.tool()
def input_text(text: str):
    """在当前焦点输入框中输入文本
    
    参数:
    - text: 要输入的文本
    """
    return call_proxypin_tool("input_text", {"text": text})

@mcp.tool()
def screenshot():
    """截屏并返回Base64编码的PNG图片(需要Root)"""
    return call_proxypin_tool("screenshot")

@mcp.tool()
def open_accessibility_settings():
    """打开Android无障碍设置页面"""
    return call_proxypin_tool("open_accessibility_settings")

@mcp.tool()
def shell(command: str, use_su: bool = False, timeout_ms: int = 10000):
    """执行Shell命令
    
    参数:
    - command: Shell命令
    - use_su: 使用Root权限(默认False)
    - timeout_ms: 超时时间(毫秒, 默认10000)
    """
    # HTTP超时比shell超时多5秒以确保响应能返回
    http_timeout = max(30, (timeout_ms // 1000) + 5)
    return call_proxypin_tool("shell", {
        "command": command, "use_su": use_su, "timeout_ms": timeout_ms
    }, timeout=http_timeout)


# ==================== 断点调试工具 (1.3.1+) ====================

@mcp.tool()
def add_breakpoint_rule(
    url_pattern: str,
    name: str = None,
    intercept_request: bool = True,
    intercept_response: bool = True,
    method: str = None,
    enabled: bool = True
):
    """添加断点调试规则
    
    拦截匹配URL的请求或响应,在ProxyPin UI中暂停以便手动检查和修改。
    
    参数:
    - url_pattern: URL正则表达式 (如 "api.example.com/v1/.*")
    - name: 规则名称(可选)
    - intercept_request: 拦截请求(默认True)
    - intercept_response: 拦截响应(默认True)
    - method: HTTP方法过滤(GET/POST等, 留空=所有方法)
    - enabled: 是否启用(默认True)
    """
    args = {
        "url_pattern": url_pattern,
        "intercept_request": intercept_request,
        "intercept_response": intercept_response,
        "enabled": enabled,
    }
    if name:
        args["name"] = name
    if method:
        args["method"] = method
    return call_proxypin_tool("add_breakpoint_rule", args)

@mcp.tool()
def remove_breakpoint_rule(url_pattern: str):
    """移除断点调试规则
    
    参数:
    - url_pattern: 要移除的规则的URL pattern
    """
    return call_proxypin_tool("remove_breakpoint_rule", {"url_pattern": url_pattern})

@mcp.tool()
def list_breakpoint_rules():
    """列出所有断点调试规则及其状态"""
    return call_proxypin_tool("list_breakpoint_rules")

@mcp.tool()
def toggle_breakpoint(enabled: bool):
    """全局启用/禁用断点调试功能
    
    参数:
    - enabled: True启用, False禁用
    """
    return call_proxypin_tool("toggle_breakpoint", {"enabled": enabled})


# ==================== 弱网络模拟工具 (1.3.1+) ====================

@mcp.tool()
def add_weak_network_rule(url_pattern: str, profile_id: str, enabled: bool = True):
    """添加弱网络模拟规则
    
    为匹配URL的请求模拟慢速网络、高延迟、丢包等弱网环境。
    
    参数:
    - url_pattern: URL匹配模式(支持通配符*)
    - profile_id: 预设方案ID。内置: weak(弱网), slow(慢速), g2(2G), g3(3G), g4(4G), g5(5G), wifi
    - enabled: 是否启用(默认True)
    """
    return call_proxypin_tool("add_weak_network_rule", {
        "url_pattern": url_pattern,
        "profile_id": profile_id,
        "enabled": enabled,
    })

@mcp.tool()
def add_custom_network_profile(
    name: str,
    upload_kbps: int = None,
    download_kbps: int = None,
    request_latency_ms: int = 0,
    response_latency_ms: int = 0,
    jitter_ms: int = 0,
    loss_rate: float = 0.0,
    offline: bool = False
):
    """创建自定义弱网络预设方案
    
    参数:
    - name: 方案名称
    - upload_kbps: 上传带宽限制(kbps, None=不限)
    - download_kbps: 下载带宽限制(kbps, None=不限)
    - request_latency_ms: 请求延迟(毫秒, 默认0)
    - response_latency_ms: 响应延迟(毫秒, 默认0)
    - jitter_ms: 抖动(毫秒, 默认0)
    - loss_rate: 丢包率0.0-1.0(默认0)
    - offline: 模拟离线模式(默认False)
    
    返回自定义profile_id,可用于add_weak_network_rule
    """
    args = {"name": name}
    if upload_kbps is not None:
        args["upload_kbps"] = upload_kbps
    if download_kbps is not None:
        args["download_kbps"] = download_kbps
    if request_latency_ms:
        args["request_latency_ms"] = request_latency_ms
    if response_latency_ms:
        args["response_latency_ms"] = response_latency_ms
    if jitter_ms:
        args["jitter_ms"] = jitter_ms
    if loss_rate:
        args["loss_rate"] = loss_rate
    if offline:
        args["offline"] = offline
    return call_proxypin_tool("add_custom_network_profile", args)

@mcp.tool()
def list_weak_network_rules():
    """列出所有弱网络模拟规则和预设方案"""
    return call_proxypin_tool("list_weak_network_rules")

@mcp.tool()
def remove_weak_network_rule(url_pattern: str):
    """移除弱网络模拟规则
    
    参数:
    - url_pattern: 要移除的规则的URL pattern
    """
    return call_proxypin_tool("remove_weak_network_rule", {"url_pattern": url_pattern})

@mcp.tool()
def toggle_weak_network(enabled: bool):
    """全局启用/禁用弱网络模拟功能
    
    参数:
    - enabled: True启用, False禁用
    """
    return call_proxypin_tool("toggle_weak_network", {"enabled": enabled})


# ==================== 环境变量管理工具 (1.3.1+) ====================

@mcp.tool()
def list_environments():
    """列出所有环境及其变量
    
    返回:
    - enabled: 环境变量功能是否启用
    - active_id: 当前激活的环境ID
    - environments: 所有环境列表(包含Global和命名环境)
    - flat_variables: 当前生效的变量映射(active覆盖global)
    """
    return call_proxypin_tool("list_environments")

@mcp.tool()
def set_environment_variable(
    key: str,
    value: str = None,
    environment_id: str = None,
    enabled: bool = True
):
    """设置或更新环境变量
    
    变量可在请求中使用 {{variable_name}} 语法引用,支持在URL、Header、Body中渲染。
    
    参数:
    - key: 变量名
    - value: 变量值(传None删除变量)
    - environment_id: 目标环境ID(默认写入当前激活环境或Global)
    - enabled: 是否启用该变量(默认True)
    """
    args = {"key": key}
    if value is not None:
        args["value"] = value
    if environment_id:
        args["environment_id"] = environment_id
    args["enabled"] = enabled
    return call_proxypin_tool("set_environment_variable", args)

@mcp.tool()
def create_environment(name: str):
    """创建新的命名环境(如Dev/Staging/Prod)
    
    参数:
    - name: 环境名称
    
    返回: 新环境的ID
    """
    return call_proxypin_tool("create_environment", {"name": name})

@mcp.tool()
def set_active_environment(environment_id: str = None):
    """设置当前激活的环境
    
    参数:
    - environment_id: 环境ID(传None或空字符串取消激活,只保留Global)
    """
    args = {}
    if environment_id:
        args["environment_id"] = environment_id
    return call_proxypin_tool("set_active_environment", args)

@mcp.tool()
def remove_environment(environment_id: str):
    """移除命名环境(不能移除Global环境)
    
    参数:
    - environment_id: 要移除的环境ID
    """
    return call_proxypin_tool("remove_environment", {"environment_id": environment_id})

@mcp.tool()
def toggle_environment_variables(enabled: bool):
    """全局启用/禁用环境变量功能
    
    参数:
    - enabled: True启用, False禁用(禁用后{{var}}不会被渲染)
    """
    return call_proxypin_tool("toggle_environment_variables", {"enabled": enabled})


if __name__ == "__main__":
    mcp.run()
