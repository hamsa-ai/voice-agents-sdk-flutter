/// connection states for the Hamsa voice agent
enum HamsaConnectionStatus {
  disconnected,
  connecting,
  connected,
  error,
}

/// agent interaction states
enum HamsaAgentState {
  idle,
  initializing,
  listening,
  thinking,
  speaking,
}

/// event data for call started
class HamsaCallStartedData {
  final String jobId;
  HamsaCallStartedData({required this.jobId});
}

/// API log entry for troubleshooting
class HamsaApiLog {
  final DateTime timestamp;
  final String method;
  final String url;
  final Map<String, String> requestHeaders;
  final String? requestBody;
  final int? statusCode;
  final String? responseBody;
  final String? error;
  final Duration? duration;

  HamsaApiLog({
    required this.timestamp,
    required this.method,
    required this.url,
    required this.requestHeaders,
    this.requestBody,
    this.statusCode,
    this.responseBody,
    this.error,
    this.duration,
  });

  bool get isSuccess => statusCode != null && statusCode! >= 200 && statusCode! < 300;
  bool get isError => error != null || (statusCode != null && statusCode! >= 400);
}

/// Definition of a parameter for a client-side tool.
/// Describes the input that the function expects from the agent.
class HamsaToolParameter {
  /// Name of the parameter.
  final String name;

  /// Data type of the parameter (e.g., 'string', 'number', 'boolean').
  final String type;

  /// Description of what the parameter represents.
  final String description;

  const HamsaToolParameter({
    required this.name,
    required this.type,
    required this.description,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': type,
        'description': description,
      };
}

/// Definition of a client-side tool that can be called by the voice agent.
///
/// Tools allow agents to execute custom functions in the client environment,
/// such as retrieving user data, making API calls, or performing calculations.
class HamsaTool {
  /// Unique name for the function (used by agent to identify the tool).
  final String functionName;

  /// Clear description of what the function does.
  final String description;

  /// Array of parameters the function accepts.
  final List<HamsaToolParameter>? parameters;

  /// Array of parameter names that are required for the function.
  final List<String>? required;

  const HamsaTool({
    required this.functionName,
    required this.description,
    this.parameters,
    this.required,
  });

  Map<String, dynamic> toJson() => {
        'function_name': functionName,
        'description': description,
        if (parameters != null)
          'parameters': parameters!.map((p) => p.toJson()).toList(),
        if (required != null) 'required': required,
      };
}

/// A tool call delivered by the Render Engine during an interactive call.
class HamsaToolCall {
  /// Name of the tool (e.g. 'show_options', 'enter_text').
  final String name;

  /// Parsed JSON arguments from the agent.
  final Map<String, dynamic> args;

  /// Unique ID for this invocation — pass back to [HamsaVoiceAgent.resolveToolCall].
  final String callId;

  const HamsaToolCall({
    required this.name,
    required this.args,
    required this.callId,
  });

  /// Whether this tool requires user interaction before resolving.
  /// show_info and dismiss_tool_ui resolve immediately on the SDK side.
  bool get isBlocking => name != 'show_info' && name != 'dismiss_tool_ui';
}
