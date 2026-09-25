part of 'mcp_server.dart';

  List<Map<String, dynamic>> _buildToolsList() {
    return [
      {
        'name': 'set_config',
        'description':
            'Update ProxyPin configuration (system proxy, SSL capture). Call this when ' 
            'the user wants to turn system-wide proxy or HTTPS decryption on or off, or ' 
            'change which hosts get captured.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'system_proxy': {
              'type': 'boolean',
              'description': 'Enable/Disable system proxy',
            },
            'ssl_capture': {
              'type': 'boolean',
              'description': 'Enable/Disable SSL capture (MITM)',
            },
          },
        },
      },
      {
        'name': 'export_har',
        'description':
            'Export captured requests to HAR (HTTP Archive) format. Call this when the ' 
            'user wants to save traffic into a file, or hand it to another tool such as ' 
            'Chrome DevTools, Charles or Postman.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'limit': {
              'type': 'integer',
              'description': 'Max requests to export (default 100)',
            },
            'request_ids': {
              'type': 'array',
              'items': {'type': 'string'},
              'description': 'Specific request IDs to export',
            },
          },
        },
      },
      {
        'name': 'import_har',
        'description':
            'Import HAR (HTTP Archive) data into the current ProxyPin session. Call this ' 
            'when the user has a .har file from another tool and wants to inspect or ' 
            'replay it inside ProxyPin.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'har_content': {
              'type': 'string',
              'description': 'HAR JSON content string',
            },
          },
          'required': ['har_content'],
        },
      },
      {
        'name': 'search_requests',
        'description':
            'Search and filter captured HTTP requests by URL, method, status code, header ' 
            'or body content. Call this when the user asks for a subset such as all 500 ' 
            'responses or every request containing a token, instead of listing ' 
            'everything.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'query': {'type': 'string', 'description': 'Keyword in URL'},
            'method': {
              'type': 'string',
              'description': 'HTTP Method (GET, POST...)',
            },
            'status_code': {
              'type': 'string',
              'description': 'Status code pattern (e.g. "200", "4xx", "5xx")',
            },
            'domain': {'type': 'string', 'description': 'Domain name filter'},
            'header_search': {
              'type': 'string',
              'description':
                  'Search in request/response headers (key or value)',
            },
            'request_body_search': {
              'type': 'string',
              'description': 'Search in request body',
            },
            'response_body_search': {
              'type': 'string',
              'description': 'Search in response body',
            },
            'min_duration': {
              'type': 'integer',
              'description': 'Minimum duration in ms',
            },
            'max_duration': {
              'type': 'integer',
              'description': 'Maximum duration in ms',
            },
            'limit': {
              'type': 'integer',
              'description': 'Max results (default 20)',
            },
          },
        },
      },
      {
        'name': 'generate_code',
        'description':
            'Generate code for a specific request in Python, JavaScript, Go, Node.js or ' 
            'cURL. Call this when the user wants to reproduce a captured call in code; ' 
            'use get_curl when only a shell one-liner is needed.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'request_id': {
              'type': 'string',
              'description': 'The ID of the request',
            },
            'language': {
              'type': 'string',
              'description': 'Target language: python, js, go, nodejs, curl',
              'enum': ['python', 'js', 'go', 'nodejs', 'curl'],
            },
          },
          'required': ['request_id', 'language'],
        },
      },
      {
        'name': 'get_curl',
        'description':
            'Generate a cURL command for a specific request. Call this when the user ' 
            'wants a quick copy-paste shell command; use generate_code when a real ' 
            'language binding is needed.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'request_id': {
              'type': 'string',
              'description': 'The ID of the request',
            },
          },
          'required': ['request_id'],
        },
      },
      {
        'name': 'get_recent_requests',
        'description':
            'List recent HTTP requests, with domain and time filters, paging and a ' 
            'compact mode for token-efficient reads. Call this first when the user asks ' 
            'to see traffic, then follow up with get_request_details for a specific id.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'limit': {
              'type': 'integer',
              'description': 'Max number of requests (default 20)',
            },
            'url_filter': {
              'type': 'string',
              'description': 'Filter by URL keyword',
            },
            'method': {
              'type': 'string',
              'description': 'Filter by HTTP Method (GET, POST...)',
            },
            'domain': {
              'type': 'string',
              'description': 'Filter by host / domain keyword',
            },
            'since_time': {
              'type': 'string',
              'description': 'Only requests at/after this time (YYYY-MM-DD or YYYY-MM-DD HH:mm)',
            },
            'end_time': {
              'type': 'string',
              'description': 'Only requests at/before this time (YYYY-MM-DD or YYYY-MM-DD HH:mm)',
            },
            'page': {
              'type': 'integer',
              'description': 'Page index (0-based) to page through older data (default 0)',
            },
            'compact': {
              'type': 'boolean',
              'description':
                  'If true, return core fields only (id/method/url/status/duration/contentType) to cut tokens',
            },
          },
        },
      },
      {
        'name': 'get_request_details',
        'description':
            '''Get full details (headers, body) of a specific request.

Response includes:
- request.body: Request body content
- request.bodySize: Body size in bytes
- request.bodyEncoding: Encoding type ('utf8', 'base64', or 'none')
- response.body: Response body content
- response.bodySize: Body size in bytes
- response.bodyEncoding: Encoding type ('utf8', 'base64', or 'none')

Body Encoding Rules:
- bodyEncoding='utf8': Text data (JSON, HTML, XML, etc.), use directly
- bodyEncoding='base64': Binary data (images, files, etc.), decode with base64.b64decode() in Python
- bodyEncoding='none': Empty body

Call this when the user asks for the headers or body of one specific request; take the
request_id from get_recent_requests or search_requests.''',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'request_id': {
              'type': 'string',
              'description': 'The ID of the request',
            },
          },
          'required': ['request_id'],
        },
      },
      {
        'name': 'start_proxy',
        'description':
            'Start the ProxyPin server on a specific port. Call this when the user wants ' 
            'to begin capturing, or right after stop_proxy; use get_proxy_status first if ' 
            'unsure whether it is already running.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'port': {
              'type': 'integer',
              'description': 'Port number (default 9099)',
            },
          },
        },
      },
      {
        'name': 'stop_proxy',
        'description':
            'Stop the ProxyPin proxy server and release the listening port. Call this when the user asks to stop '
                'capturing traffic, or before changing ports/config that require a restart.',
        'inputSchema': {'type': 'object', 'properties': {}},
      },
      {
        'name': 'get_proxy_status',
        'description':
            'Get the current status of the proxy server (running, port, address, LAN ' 
            'mode). Call this when you need to know whether capture is active, or before ' 
            'starting and stopping it.',
        'inputSchema': {'type': 'object', 'properties': {}},
      },
      {
        'name': 'clear_requests',
        'description':
            'Clear all captured requests (session history and UI list). Call this when ' 
            'the user wants a fresh start or to free memory; it discards data, so confirm ' 
            'unless the traffic is obviously disposable.',
        'inputSchema': {'type': 'object', 'properties': {}},
      },
      {
        'name': 'replay_request',
        'description':
            'Replay (resend) a captured HTTP request. Call this when the user wants to ' 
            'repeat a call, for example to reproduce a bug or to verify a fix after ' 
            'changing a script or a rewrite rule.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'request_id': {
              'type': 'string',
              'description': 'The ID of the request to replay',
            },
          },
          'required': ['request_id'],
        },
      },
      {
        'name': 'update_script',
        'description':
            'Create or update a JavaScript script that rewrites requests and responses. ' 
            'Call this when the user wants to inject, mock or sign traffic; check ' 
            'get_scripts or get_script_detail first if the script may already exist.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'name': {'type': 'string', 'description': 'Script name'},
            'url_pattern': {
              'type': 'string',
              'description': 'URL pattern to match (supports wildcard *)',
            },
            'script_content': {
              'type': 'string',
              'description': 'JavaScript code (onRequest/onResponse functions)',
            },
          },
          'required': ['name', 'url_pattern', 'script_content'],
        },
      },
      {
        'name': 'get_scripts',
        'description':
            'List all configured JavaScript rewrite scripts with their enabled state and match rules. Call this when '
                'the user asks which scripts exist, or before editing one with update_script.',
        'inputSchema': {'type': 'object', 'properties': {}},
      },
      {
        'name': 'get_statistics',
        'description':
            'Get statistics of captured requests (methods, status codes, domains, sizes, ' 
            'durations). Call this when the user asks for an overview such as the error ' 
            'rate or the busiest domains.',
        'inputSchema': {'type': 'object', 'properties': {}},
      },
      {
        'name': 'compare_requests',
        'description':
            'Compare two requests side by side. Call this when the user wants to know ' 
            'what differs between two calls, such as before and after a fix, or two login ' 
            'attempts.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'request_id_1': {
              'type': 'string',
              'description': 'First request ID',
            },
            'request_id_2': {
              'type': 'string',
              'description': 'Second request ID',
            },
          },
          'required': ['request_id_1', 'request_id_2'],
        },
      },
      {
        'name': 'find_similar_requests',
        'description':
            'Find requests similar to a given one (same URL pattern, method). Call this ' 
            'when the user wants to see every call to the same endpoint, for example to ' 
            'check whether a behaviour is consistent.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'request_id': {
              'type': 'string',
              'description': 'Reference request ID',
            },
            'limit': {
              'type': 'integer',
              'description': 'Max results (default 10)',
            },
          },
          'required': ['request_id'],
        },
      },
      {
        'name': 'extract_api_endpoints',
        'description':
            'Extract and group unique API endpoints from captured traffic. Call this when ' 
            'the user wants the API surface of a host or an app rather than individual ' 
            'requests.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'domain_filter': {
              'type': 'string',
              'description': 'Filter by domain (optional)',
            },
          },
        },
      },
      // ==================== 安全分析工具（2.x 增强） ====================
      {
        'name': 'find_sensitive_data',
        'description':
            'Search captured requests for sensitive data: passwords, API keys, tokens, ' 
            'secrets, private keys, phone numbers and ID cards. Call this when the user ' 
            'asks whether secrets leak in traffic, or wants a request checked before ' 
            'sharing it.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'request_id': {
              'type': 'string',
              'description':
                  'Specific request ID (optional, defaults to recent 100)',
            },
            'search_body': {
              'type': 'boolean',
              'description': 'Search request bodies (default true)',
            },
          },
        },
      },
      {
        'name': 'get_cookie_info',
        'description':
            'Get cookie analysis for a domain or request (names, values, HttpOnly, ' 
            'Secure, domains). Call this when the user asks about session cookies or why ' 
            'a request appears unauthenticated.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'domain': {
              'type': 'string',
              'description': 'Domain to filter (e.g. example.com)',
            },
            'request_id': {
              'type': 'string',
              'description': 'Specific request ID (overrides domain)',
            },
          },
        },
      },
      {
        'name': 'get_domain_summary',
        'description':
            'Get a traffic summary for one domain (methods, status codes, average ' 
            'duration, error count). Call this when the user asks how a particular host ' 
            'is behaving.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'domain': {
              'type': 'string',
              'description': 'Domain to analyze (required)',
            },
          },
          'required': ['domain'],
        },
      },
      // ==================== Breakpoint Debugging Tools (1.3.1+) ====================
      {
        'name': 'toggle_breakpoint',
        'description':
            'Enable or disable breakpoint debugging globally. Call this when the user ' 
            'wants to pause traffic for manual inspection; pair it with ' 
            'get_pending_intercepts, approve_intercept and reject_intercept.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'enabled': {
              'type': 'boolean',
              'description': 'true to enable, false to disable',
            },
          },
          'required': ['enabled'],
        },
      },
      // ==================== Weak Network Simulation Tools (1.3.1+) ====================
      {
        'name': 'add_weak_network_rule',
        'description':
            'Add a weak-network simulation rule for a URL pattern (bandwidth limit, ' 
            'latency, jitter, packet loss or offline). Call this when the user wants to ' 
            'test how an app behaves on a poor connection.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'url_pattern': {
              'type': 'string',
              'description': 'URL pattern to match (supports wildcard *)',
            },
            'profile_id': {
              'type': 'string',
              'description':
                  'Preset profile ID. Built-in: weak, slow, g2, g3, g4, g5, wifi. Or use a custom profile ID.',
            },
            'enabled': {
              'type': 'boolean',
              'description': 'Enable this rule (default true)',
            },
          },
          'required': ['url_pattern', 'profile_id'],
        },
      },
      {
        'name': 'add_custom_network_profile',
        'description':
            'Create a custom weak-network profile with specific parameters (bandwidth, ' 
            'latency, jitter, loss rate). Call this before add_weak_network_rule when ' 
            'none of the built-in profiles match the conditions to simulate.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'name': {'type': 'string', 'description': 'Profile name'},
            'upload_kbps': {
              'type': 'integer',
              'description':
                  'Upload bandwidth limit in kbps (null = unlimited)',
            },
            'download_kbps': {
              'type': 'integer',
              'description':
                  'Download bandwidth limit in kbps (null = unlimited)',
            },
            'request_latency_ms': {
              'type': 'integer',
              'description': 'Request latency in milliseconds (default 0)',
            },
            'response_latency_ms': {
              'type': 'integer',
              'description': 'Response latency in milliseconds (default 0)',
            },
            'jitter_ms': {
              'type': 'integer',
              'description': 'Jitter in milliseconds (default 0)',
            },
            'loss_rate': {
              'type': 'number',
              'description': 'Packet loss rate 0.0-1.0 (default 0)',
            },
            'offline': {
              'type': 'boolean',
              'description': 'Simulate offline mode (default false)',
            },
          },
          'required': ['name'],
        },
      },
      {
        'name': 'list_weak_network_rules',
        'description':
            'List all weak-network simulation rules and profiles. Call this when the user ' 
            'asks which network conditions are configured, or to get a profile_id for ' 
            'add_weak_network_rule.',
        'inputSchema': {'type': 'object', 'properties': {}},
      },
      {
        'name': 'remove_weak_network_rule',
        'description':
            'Remove a weak-network rule by URL pattern. Call this when the user wants to ' 
            'stop simulating poor conditions for a specific pattern.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'url_pattern': {
              'type': 'string',
              'description': 'URL pattern of the rule to remove',
            },
          },
          'required': ['url_pattern'],
        },
      },
      {
        'name': 'toggle_weak_network',
        'description':
            'Enable or disable weak-network simulation globally. Call this when the user ' 
            'wants to turn the feature on or off without deleting individual rules.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'enabled': {
              'type': 'boolean',
              'description': 'true to enable, false to disable',
            },
          },
          'required': ['enabled'],
        },
      },
      // ==================== Environment Variable Tools (1.3.1+) ====================
      {
        'name': 'list_environments',
        'description':
            'List all environments and their variables, and which one is active. Call ' 
            'this when the user asks what variables exist, or before switching ' 
            'environments.',
        'inputSchema': {'type': 'object', 'properties': {}},
      },
      {
        'name': 'set_environment_variable',
        'description':
            'Set or update an environment variable, referenced in requests as ' 
            '{{variable_name}}. Call this when the user wants to change a value such as a ' 
            'host, token or version across many requests at once.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'key': {'type': 'string', 'description': 'Variable name'},
            'value': {
              'type': 'string',
              'description': 'Variable value (null to delete)',
            },
            'environment_id': {
              'type': 'string',
              'description':
                  'Target environment ID (default: global or active environment)',
            },
            'enabled': {
              'type': 'boolean',
              'description': 'Enable the variable (default true)',
            },
          },
          'required': ['key'],
        },
      },
      {
        'name': 'create_environment',
        'description':
            'Create a new named environment (e.g. Dev, Staging, Prod). Call this when the ' 
            'user needs a separate variable set for a different backend, then use ' 
            'set_active_environment to switch to it.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'name': {'type': 'string', 'description': 'Environment name'},
          },
          'required': ['name'],
        },
      },
      {
        'name': 'set_active_environment',
        'description':
            'Set the active environment by id, or pass null to deactivate it (only Global ' 
            'remains). Call this when the user wants requests to pick up a different ' 
            'variable set.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'environment_id': {
              'type': 'string',
              'description':
                  'Environment ID to activate, or empty string to deactivate',
            },
          },
        },
      },
      {
        'name': 'remove_environment',
        'description':
            'Remove a named environment by id; the Global environment cannot be removed. ' 
            'Call this when the user wants to delete a variable set that is no longer ' 
            'needed.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'environment_id': {
              'type': 'string',
              'description': 'Environment ID to remove',
            },
          },
          'required': ['environment_id'],
        },
      },
      {
        'name': 'toggle_environment_variables',
        'description':
            'Enable or disable the environment variable feature globally. Call this when ' 
            'the user wants {{...}} placeholders left untouched, for example while ' 
            'debugging substitution.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'enabled': {
              'type': 'boolean',
              'description': 'true to enable, false to disable',
            },
          },
          'required': ['enabled'],
        },
      },
      // ==================== Device Control Tools (Android only) ====================
      {
        'name': 'get_device_info',
        'description':
            'Get Android device info (model, brand, Android version, WiFi IP, root and ' 
            'accessibility status). Call this first when device automation is needed: the ' 
            'root and accessibility flags tell you which other device tools will actually ' 
            'work.',
        'inputSchema': {'type': 'object', 'properties': {}},
      },
      {
        'name': 'get_current_activity',
        'description':
            'Get the current foreground activity and package name. Call this when the ' 
            'user asks which app is in front, or before driving a specific app with the ' 
            'tap and input tools.',
        'inputSchema': {'type': 'object', 'properties': {}},
      },
      {
        'name': 'dump_ui',
        'description':
            'Dump the current Android UI hierarchy as a JSON array of elements. Call this ' 
            'when you need to locate a control by text or id before tapping it, which is ' 
            'more reliable than guessing coordinates.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'clickable_only': {
              'type': 'boolean',
              'description': 'Only include clickable elements (default false)',
            },
            'package_filter': {
              'type': 'string',
              'description': 'Filter by package name',
            },
          },
        },
      },
      {
        'name': 'tap_screen',
        'description':
            'Perform a tap at the given screen coordinates. Call this when the user wants ' 
            'to press somewhere on the device; prefer dump_ui to find the coordinates ' 
            'rather than guessing.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'x': {'type': 'integer', 'description': 'X coordinate'},
            'y': {'type': 'integer', 'description': 'Y coordinate'},
          },
          'required': ['x', 'y'],
        },
      },
      {
        'name': 'long_press',
        'description':
            'Perform a long press at the given coordinates for a duration. Call this when ' 
            'a plain tap is not enough, for example to open a context menu or trigger a ' 
            'copy action.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'x': {'type': 'integer', 'description': 'X coordinate'},
            'y': {'type': 'integer', 'description': 'Y coordinate'},
            'duration': {
              'type': 'integer',
              'description': 'Press duration in ms (default 50)',
            },
          },
          'required': ['x', 'y'],
        },
      },
      {
        'name': 'swipe_screen',
        'description':
            'Perform a swipe gesture from one point to another. Call this when the user ' 
            'wants to scroll a list, dismiss a card or reveal a drawer; adjust the ' 
            'duration for a fling instead of a slow drag.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'x1': {'type': 'integer', 'description': 'Start X'},
            'y1': {'type': 'integer', 'description': 'Start Y'},
            'x2': {'type': 'integer', 'description': 'End X'},
            'y2': {'type': 'integer', 'description': 'End Y'},
            'duration': {
              'type': 'integer',
              'description': 'Swipe duration in ms (default 300)',
            },
          },
          'required': ['x1', 'y1', 'x2', 'y2'],
        },
      },
      {
        'name': 'key_event',
        'description':
            'Send a hardware key event. Keycodes: 3=HOME, 4=BACK, 26=POWER, 82=MENU, ' 
            '187=RECENTS. Call this when the user wants to navigate back or home, or wake ' 
            'the screen.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'keycode': {
              'type': 'integer',
              'description':
                  'Android keycode (3=HOME, 4=BACK, 26=POWER, 82=MENU, 187=RECENTS)',
            },
          },
          'required': ['keycode'],
        },
      },
      {
        'name': 'input_text',
        'description':
            'Set text on the currently focused input element. Call this when the user ' 
            'wants to type into a field; tap it first so that it has focus.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'text': {'type': 'string', 'description': 'Text to input'},
          },
          'required': ['text'],
        },
      },
      {
        'name': 'screenshot',
        'description':
            'Take a screenshot and return it as Base64 PNG (requires root). Call this ' 
            'when the user wants to see the current screen, or to visually confirm the ' 
            'result of a tap or input sequence.',
        'inputSchema': {'type': 'object', 'properties': {}},
      },
      {
        'name': 'open_accessibility_settings',
        'description':
            'Open the Android accessibility settings page. Call this when the ' 
            'accessibility permission is missing and the device tools (tap, dump_ui, ' 
            'screenshot) are failing for that reason.',
        'inputSchema': {'type': 'object', 'properties': {}},
      },
      {
        'name': 'shell',
        'description':
            'Execute a shell command on the device, optionally with root, Shizuku or ' 
            'Dhizuku. Call this when the user needs something the dedicated tools do not ' 
            'cover; it is powerful, so keep commands narrow and reversible.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'command': {
              'type': 'string',
              'description': 'Shell command to execute',
            },
            'use_su': {
              'type': 'boolean',
              'description': 'Use root (su) for execution (default false)',
            },
            'mode': {
              'type': 'string',
              'enum': ['auto', 'root', 'shizuku', 'dhizuku'],
              'description':
                  'Permission mode: root=su, shizuku=Shizuku service, dhizuku=Dhizuku device owner, auto=pick best available (default auto)',
            },
            'timeout_ms': {
              'type': 'integer',
              'description': 'Timeout in milliseconds (default 10000)',
            },
          },
          'required': ['command'],
        },
      },
      {
        'name': 'get_pending_intercepts',
        'description':
            'Get all requests and responses currently paused by breakpoint interception. ' 
            'Call this when the user wants to see what is waiting for a decision, then ' 
            'approve_intercept or reject_intercept each one.',
        'inputSchema': {'type': 'object', 'properties': {}},
      },
      {
        'name': 'approve_intercept',
        'description':
            'Approve (release) a paused intercept, optionally modifying the request ' 
            'first. Call this to let a frozen request continue, with or without edits.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'request_id': {
              'type': 'string',
              'description': 'ID of the paused intercept',
            },
            'modifier': {
              'type': 'object',
              'description':
                  'Optional request modifications: method, url, headers, body',
              'properties': {
                'method': {'type': 'string'},
                'url': {'type': 'string'},
                'headers': {'type': 'object'},
                'body': {'type': 'string'},
              },
            },
          },
          'required': ['request_id'],
        },
      },
      {
        'name': 'reject_intercept',
        'description':
            'Reject a paused intercept; the request is aborted and the response is ' 
            'dropped. Call this when the user wants to block a specific call rather than ' 
            'edit it.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'request_id': {
              'type': 'string',
              'description': 'ID of the paused intercept',
            },
            'reason': {
              'type': 'string',
              'description': 'Rejection reason (optional)',
            },
          },
          'required': ['request_id'],
        },
      },
      // ==================== WebSocket Message Tools (v1.6.0+) ====================
      {
        'name': 'get_paused_websocket_messages',
        'description':
            'Get all WebSocket messages currently paused by interception. Call this when ' 
            'the user wants to inspect or decide on frozen WebSocket frames.',
        'inputSchema': {'type': 'object', 'properties': {}},
      },
      {
        'name': 'resume_websocket_message',
        'description':
            'Resume (release) a paused WebSocket message, optionally replacing the ' 
            'payload. Call this to let a frozen frame through, with or without edits.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'frame_id': {
              'type': 'string',
              'description': 'ID of the paused WebSocket frame',
            },
            'payload': {
              'type': 'string',
              'description': 'Optional modified payload (text messages only)',
            },
          },
          'required': ['frame_id'],
        },
      },
      {
        'name': 'abort_websocket_message',
        'description':
            'Abort a paused WebSocket message so it is dropped. Call this when the user ' 
            'wants to block a specific frame.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'frame_id': {
              'type': 'string',
              'description': 'ID of the paused WebSocket frame',
            },
            'reason': {
              'type': 'string',
              'description': 'Abort reason (optional)',
            },
          },
          'required': ['frame_id'],
        },
      },
      {
        'name': 'diagnose_capture',
        'description':
            'Run a read-only self-check of the capture pipeline: whether the proxy server is running, '
                'whether the system proxy points at this app, whether the CA certificate is trusted, '
                'and whether any traffic arrived recently. Returns structured findings plus actionable '
                'suggestions. Call this first when the user says requests cannot be captured, pages fail '
                'to load, or traffic suddenly stops.',
        'inputSchema': {'type': 'object', 'properties': {}},
      },
      {
        'name': 'get_quic_sessions',
        'description':
            'List QUIC/HTTP-3 connections observed by the passive VPN probe, with per-session '
                'metadata (SNI host, QUIC version, remote endpoint, packet/byte counts, last-seen) and '
                'a rolling 10-minute traffic timeline. Also reports how many TLS key-log entries have '
                'been imported and, for sessions whose keys are available, a preview of decrypted '
                '1-RTT stream data. HTTP/3 HEADERS are decoded with QPACK (static + dynamic table; '
                'dynamic table state is reconstructed per connection from the QPACK encoder stream) '
                'and returned as structured headers. Call this when the user asks which apps/domains '
                'use QUIC, why a QUIC connection cannot be decrypted, or wants an overview of QUIC '
                'traffic.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'host_filter': {
              'type': 'string',
              'description': 'Only return sessions whose SNI host contains this text (optional)',
            },
            'limit': {
              'type': 'integer',
              'description': 'Maximum number of sessions to return (default 50)',
            },
          },
        },
      },
      {
        'name': 'get_security_audit',
        'description':
            'Run the passive security self-audit over already-captured traffic: flags cleartext '
                'HTTP, leaked secrets/tokens, cookies missing Secure/HttpOnly, missing security '
                'response headers, verbose server fingerprints, over-permissive CORS, unsigned or '
                'expiring JWTs, plus two injection traces visible in the responses themselves — '
                'database error messages echoed back (sqli) and request parameters reflected into '
                'HTML without encoding (xss). Every check is passive and read-only: it only inspects '
                'traffic you already captured and never sends requests, injects payloads or probes '
                'targets. Returns counts per severity and per category, plus the matched issues with '
                'fix suggestions. Call this when the user asks whether the captured API has security '
                'problems, whether input handling looks unsafe, or wants a security review of recent '
                'traffic.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'severity': {
              'type': 'string',
              'enum': ['high', 'medium', 'low', 'info'],
              'description': 'Only return issues of this severity (optional)',
            },
            'category': {
              'type': 'string',
              'description': 'Only return issues in these categories, comma separated '
                  '(transport, headers, credentials, sqli, xss, disclosure, privacy, custom)',
            },
            'limit': {
              'type': 'integer',
              'description': 'Maximum number of issues to return (default 100)',
            },
          },
        },
      },
      {
        'name': 'get_performance_metrics',
        'description':
            'Report runtime performance metrics: process memory usage (current and peak RSS) and '
                'aggregate capture statistics (request counts by method/status/domain, total size, '
                'average duration, error count). Call this when the user asks how much memory the app '
                'uses, whether capture is slowing things down, or wants a performance overview.',
        'inputSchema': {'type': 'object', 'properties': {}},
      },
      // ---- 合并后的扩展工具 ----
      {
        'name': 'get_ssl_proxying_list',
        'description':
            'Show the SSL (HTTPS) capture scope: whitelist and blacklist domain rules and whether each is '
                'enabled. Call this when the user asks why some HTTPS traffic is not decrypted, or wants to see '
                'the current SSL capture rules.',
        'inputSchema': {'type': 'object', 'properties': {}},
      },
      {
        'name': 'get_tool_catalog',
        'description':
            'Return this server\'s tool catalog grouped by capability (capture / rules / scripts / ssl / device / '
                'security / environment / runtime / meta ...). Call this first when the task is broad or you are '
                'unsure which tool to use, then call tools/list for the full JSON schema of the ones you need.',
        'inputSchema': {'type': 'object', 'properties': {}},
      },
      {
        'name': 'get_client_setup',
        'description':
            'Return connection details for hooking an AI client up to this ProxyPin MCP server: endpoint, '
                'whether a Bearer token is required, and ready-to-paste commands for Claude Code / Codex / curl, '
                'plus the desktop stdio bridge command. Call this when the user asks how to connect an IDE or CLI.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'client': {
              'type': 'string',
              'description': 'Optional: claude | codex | cursor | curl | stdio (omit to get all)',
            },
          },
        },
      },
      {
        'name': 'keep_alive',
        'description':
            'Manage Android keep-alive for this app (or another package) so the MCP server and '
                'capture keep running in the background. Actions: status | enable | disable | apply | '
                'restore. It works through the adb-shell command set (deviceidle whitelist, appops '
                'RUN_*_IN_BACKGROUND, am set-inactive) executed over Shizuku, root or Dhizuku - no '
                'extra app install is needed, but one of those permission channels must be available. '
                'Call this when the user asks why capture stops in the background, wants the app to '
                'survive battery optimisation, or asks to turn keep-alive on or off.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'action': {
              'type': 'string',
              'enum': ['status', 'enable', 'disable', 'apply', 'restore'],
              'description': 'status=query only; enable/disable=persist the setting and apply; '
                  'apply=force apply now; restore=undo the changes (default status)',
            },
            'mode': {
              'type': 'string',
              'enum': ['auto', 'root', 'shizuku', 'dhizuku'],
              'description': 'Permission channel: auto picks the best available (default auto)',
            },
            'package': {
              'type': 'string',
              'description': 'Target package name; omit to use this app itself',
            },
          },
        },
      },
      {
        'name': 'get_mcp_audit',
        'description':
            'Read the MCP server audit log: recent tool calls with caller, duration, success flag, '
                'error message and argument names (argument values are never recorded, to avoid '
                'leaking captured traffic or credentials). Call this when the user asks what tools '
                'were called, why an AI client failed, or wants to review recent MCP activity.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'limit': {
              'type': 'integer',
              'description': 'Maximum number of records to return (default 50, newest last)',
            },
            'tool': {
              'type': 'string',
              'description': 'Only return records for this tool name (optional)',
            },
            'only_failed': {
              'type': 'boolean',
              'description': 'Only return failed calls (optional)',
            },
          },
        },
      },
      {
        'name': 'calculator',
        'description':
            'One entry point for 27 calculation / conversion operations - the whole calculator. '
                'Pick `op`, then pass the matching arguments. Binary ops: int_convert (any-precision '
                'integer to hex/dec/bin/oct plus 8/16/32/64-bit signed-unsigned complement, '
                'big/little-endian hex and ASCII), bitwise (and/or/xor/not/shl/shr/sar/rol/ror), '
                'endian_swap, ieee754 (float32/64 bit layout), crc (crc32/crc16_ccitt/crc16_modbus/'
                'crc16_xmodem/crc16_ibm), hash (md5/sha1/sha256/sha512), mod_op (mod_pow/mod_inverse/'
                'gcd/lcm), codec (base64/base64url/hex/url). Arithmetic: add, subtract, multiply, '
                'division, modulo, sum, floor, ceiling, round (exact for integers via big integers). '
                'Statistics: mean, median, mode, min, max. Trigonometry: sin, cos, tan, arcsin, '
                'arccos, arctan, degrees_to_radians, radians_to_degrees. Call this when analysing '
                'captured traffic and you need to decode an integer field, check a CRC, fix an '
                'endianness mistake, or do arithmetic the model should not guess at.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'op': {
              'type': 'string',
              'enum': [
                'int_convert', 'bitwise', 'endian_swap', 'ieee754', 'crc', 'hash', 'mod_op', 'codec',
                'add', 'subtract', 'multiply', 'division', 'modulo', 'sum', 'floor', 'ceiling', 'round',
                'mean', 'median', 'mode', 'min', 'max',
                'sin', 'cos', 'tan', 'arcsin', 'arccos', 'arctan',
                'degrees_to_radians', 'radians_to_degrees',
              ],
              'description': 'Which operation to run',
            },
            'value': {'type': ['string', 'number'], 'description': 'Primary input (accepts "0x..", "0b..", decimal)'},
            'a': {'type': ['string', 'number'], 'description': 'Operand A'},
            'b': {'type': ['string', 'number'], 'description': 'Operand B / shift amount'},
            'values': {'type': 'array', 'description': 'Numeric array for sum / statistics ops'},
            'width': {'type': 'integer', 'description': 'Bit width for int_convert / bitwise (default 64 / 32)'},
            'widthBytes': {'type': 'integer', 'description': 'Byte width for endian_swap'},
            'operation': {'type': 'string', 'description': 'Bitwise operation name'},
            'shift': {'type': 'integer', 'description': 'Shift/rotate amount'},
            'precision': {'type': 'string', 'enum': ['float32', 'float64'], 'description': 'IEEE754 precision'},
            'algorithm': {'type': 'string', 'description': 'CRC or hash algorithm name'},
            'action': {'type': 'string', 'description': 'Sub-action for crc/hash/mod_op/codec'},
            'data': {'type': ['string', 'number'], 'description': 'Payload for crc / hash'},
            'input': {'type': ['string', 'number'], 'description': 'Payload for codec / ieee754'},
            'inputFormat': {'type': 'string', 'enum': ['hex', 'utf8', 'base64'], 'description': 'How to read data'},
            'base': {'type': ['string', 'number'], 'description': 'mod_pow base'},
            'exponent': {'type': ['string', 'number'], 'description': 'mod_pow exponent'},
            'modulus': {'type': ['string', 'number'], 'description': 'modulus'},
          },
          'required': ['op'],
        },
      },
      {
        'name': 'decode_grpc',
        'description':
            'Decode a gRPC over HTTP/2 message without its .proto file: split the length-prefixed '
                'frames, walk the protobuf wire format to recover field numbers, types and values '
                '(nested messages included), and read grpc-status / grpc-message from the trailers. '
                'Call this when you captured an application/grpc request or response and need to know '
                'which service method was called, what fields were on the wire, or why the call failed.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'body': {'type': 'string', 'description': 'Raw gRPC message body (hex or base64, see bodyFormat)'},
            'bodyFormat': {'type': 'string', 'enum': ['hex', 'base64'], 'description': 'How to read body (default hex)'},
            'contentType': {'type': 'string', 'description': 'Message content-type, e.g. application/grpc'},
            'path': {'type': 'string', 'description': 'HTTP/2 :path, e.g. /pkg.Service/Method'},
            'grpcStatus': {'type': ['string', 'number'], 'description': 'Trailer grpc-status, if captured'},
            'grpcMessage': {'type': 'string', 'description': 'Trailer grpc-message, if captured'},
          },
          'required': ['body'],
        },
      },
      {
        'name': 'batch',
        'description':
            'Run several MCP tool calls inside one request and chain their results, avoiding a '
                'round trip per step. `steps` is an ordered array of {"tool": name, "args": {...}}; a '
                'later step can pull a value out of an earlier result with a reference object of the '
                'form {"\$step": 0, "field": "result.hex"} (field supports dotted paths). Steps run in '
                'order; by default it stops at the first failure (set stop_on_error=false to continue). '
                'Nesting batch inside batch is rejected. Call this when a task needs several dependent '
                'steps, such as decode a base64 field then swap endianness then compute its CRC.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'steps': {
              'type': 'array',
              'description': 'Ordered list of {"tool": "...", "args": {...}} objects (max 20)',
            },
            'stop_on_error': {
              'type': 'boolean',
              'description': 'Stop at the first failed step (default true)',
            },
          },
          'required': ['steps'],
        },
      },
      // 官方工具源（同名者已在本表中提供，见 _nativeToolNames）
      ..._officialToolsJson(),
    ];
  }
