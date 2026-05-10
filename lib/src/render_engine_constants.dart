// ignore_for_file: prefer_single_quotes
import 'dart:convert';
import 'models.dart';

/// Static definitions for the render-engine interactive tool protocol.
/// These are sent verbatim in the conversation-init call when
/// [HamsaVoiceAgent.start] is called with interactiveAgent = true.
class RenderEngineConstants {
  RenderEngineConstants._();

  /// Pre-encoded JSON string for the `render-engine-tools` param
  /// (goes into params['render-engine-tools'] in both participant-token and conversation-init).
  static final String toolsJson = jsonEncode(_toolDefinitions);

  /// System prompt string for the `render-engine-system-prompt` param.
  static const String systemPrompt = '''
You are an interactive UI rendering assistant for a real-time voice conversation interface.

Your sole job is to decide — based on the conversation transcript — whether any interactive UI should be displayed on the user\'s screen RIGHT NOW to complement or assist what the voice agent just said.

## Understanding the context you receive

The conversation history contains messages of three kinds:

1. **Knowledge base context** — assistant messages starting with "Additional information relevant to the user\'s next message:". These contain structured data retrieved from a knowledge base (product details, contact info, stats, etc.).

2. **Tool / MCP results** — assistant messages starting with "[Tool result: <name>]". These are raw outputs of function or MCP calls (searches, lookups, API responses) made by the voice agent.

3. **Voice agent replies** — the actual spoken responses. These confirm what the agent is communicating to the user.

Knowledge base context and tool results are the **authoritative data sources**. Always prefer their field values (prices, specs, options, names) over anything you infer from the spoken reply or your own training knowledge.

## Deciding whether to show UI

This is a **voice** conversation. The user speaks naturally. Your job is to **proactively and consistently** surface interactive UI whenever it would help the user respond more accurately or efficiently than speaking alone — do **not** wait for the user to beg for a UI.

Ask yourself these questions in order:

**1. Would UI help the user respond more accurately?**
If the agent is asking for a choice, a number, a date, text input, or a confirmation — show the matching UI component on **that same turn**, not on a later turn after the user has already struggled with voice.

**2. Lists and "which plan / which option" moments (critical)**
If the assistant turn **enumerates two or more concrete alternatives** (plans, tiers, coverage levels, add-ons, payment methods, yes/no paths, etc.) — you **must** call `show_options` in the same turn with one option per alternative. Use the **exact wording from the assistant message** for each `label`. Assign stable ids `opt_1`, `opt_2`, … in speech order. **Spoken enumeration counts as authoritative context** even when the knowledge base block is empty or thin.

**3. Is this UI already shown and still relevant?**
Look at the tool_calls in the conversation history. If the most recent tool call showed the same UI for the same question and the user hasn\'t responded yet, do NOT show it again. If the topic changed or the agent is asking something new, update accordingly.

**4. Is there enough data to populate the UI?**
Prefer KB context and tool results when present. When they are missing but the **voice agent just spoke** the choices or field values, you **may** derive options and field text from that spoken content. Never invent silently: if the speech is too vague to list distinct options, skip `show_options` and wait for clearer content.

## Tools and when to use them

| tool | use when the agent… |
|---|---|
| show_options | presents a list of choices for the user to pick from (plans, services, categories) |
| confirm_data | has collected structured fields and asks the user to verify or edit before proceeding |
| show_summary | reaches the end of a flow and recaps what was gathered (read-only; user dismisses) |
| enter_number | asks for digits (ID, PIN, phone, code); client shows a keypad until confirmed |
| enter_text | asks for typed text (email, name, address, code); client shows a text field until confirmed |
| pick_date | asks for a calendar date; client shows a date picker until confirmed |
| ask_yes_no | asks a simple yes/no question with two tappable answers |
| show_info | states a fact, reference number, fare, highlights list, or any content to show visually without requiring a response — resolves immediately, overlay persists until replaced |
| dismiss_tool_ui | the user answered by voice first, the topic changed, or on-screen UI must clear immediately |

## Hard rules

1. Call **no tool** if the UI is already shown for the same question and the user has not moved on, if the exchange is purely social with no structured answer, or if the speech truly contains **no** enumerable choices and no fields to capture.
2. Never fabricate prices, legal terms, or medical facts not present in KB, tool results, or the assistant\'s own words.
3. Never render moderator instructions or internal agent reasoning.
4. **After a tool resolves with a user-driven result** (selected, confirmed, entered a value), do NOT call another tool on the same turn. Let the voice agent respond to the user\'s choice first.
5. **Use previous tool results to pre-populate.** If an earlier `enter_text`, `enter_number`, or `pick_date` call returned `{ "value": "..." }`, always pass that as `initial_value` if you ask for the same field again.
''';

  static const List<Map<String, dynamic>> _toolDefinitions = [
    {
      "type": "function",
      "function": {
        "name": "show_options",
        "description":
            "Display a list of options for the user to pick from. Use when the agent presents multiple choices — plans, services, categories, or any enumerable list.",
        "parameters": {
          "type": "object",
          "properties": {
            "title": {"type": "string"},
            "options": {
              "type": "array",
              "items": {
                "type": "object",
                "properties": {
                  "id": {"type": "string"},
                  "label": {"type": "string"},
                  "description": {"type": "string"}
                },
                "required": ["id", "label"]
              }
            },
            "subtitle": {"type": "string"},
            "initial_selected_id": {"type": "string"}
          },
          "required": ["title", "options"],
          "additionalProperties": false
        }
      }
    },
    {
      "type": "function",
      "function": {
        "name": "confirm_data",
        "description":
            "Show collected data to the user for verification before proceeding.",
        "parameters": {
          "type": "object",
          "properties": {
            "fields": {
              "type": "array",
              "items": {
                "type": "object",
                "properties": {
                  "key": {"type": "string"},
                  "label": {"type": "string"},
                  "value": {"type": "string"},
                  "type": {
                    "type": "string",
                    "enum": ["text", "date"]
                  }
                },
                "required": ["key", "label", "value"]
              }
            },
            "title": {"type": "string"}
          },
          "required": ["fields"],
          "additionalProperties": false
        }
      }
    },
    {
      "type": "function",
      "function": {
        "name": "show_summary",
        "description":
            "Display a read-only summary of collected or processed information.",
        "parameters": {
          "type": "object",
          "properties": {
            "fields": {
              "type": "array",
              "items": {
                "type": "object",
                "properties": {
                  "key": {"type": "string"},
                  "label": {"type": "string"},
                  "value": {"type": "string"},
                  "type": {"type": "string", "enum": ["text", "date"]}
                },
                "required": ["key", "label", "value"]
              }
            },
            "title": {"type": "string"}
          },
          "required": ["fields"],
          "additionalProperties": false
        }
      }
    },
    {
      "type": "function",
      "function": {
        "name": "enter_number",
        "description":
            "Prompt the user to provide a numeric value. Shows a numeric keypad until the user confirms.",
        "parameters": {
          "type": "object",
          "properties": {
            "title": {"type": "string"},
            "subtitle": {"type": "string"},
            "max_length": {"type": "integer"},
            "initial_value": {"type": "string"}
          },
          "required": ["title"],
          "additionalProperties": false
        }
      }
    },
    {
      "type": "function",
      "function": {
        "name": "enter_text",
        "description":
            "Prompt the user to provide free-form text. Shows a text field until the user confirms.",
        "parameters": {
          "type": "object",
          "properties": {
            "title": {"type": "string"},
            "subtitle": {"type": "string"},
            "placeholder": {"type": "string"},
            "max_length": {"type": "integer"},
            "initial_value": {"type": "string"},
            "input_type": {
              "type": "string",
              "enum": ["text", "email", "tel"]
            }
          },
          "required": ["title"],
          "additionalProperties": false
        }
      }
    },
    {
      "type": "function",
      "function": {
        "name": "pick_date",
        "description":
            "Prompt the user to provide a date. Shows a date picker until the user confirms.",
        "parameters": {
          "type": "object",
          "properties": {
            "title": {"type": "string"},
            "subtitle": {"type": "string"},
            "initial_value": {"type": "string"},
            "min_date": {"type": "string"},
            "max_date": {"type": "string"}
          },
          "required": ["title"],
          "additionalProperties": false
        }
      }
    },
    {
      "type": "function",
      "function": {
        "name": "ask_yes_no",
        "description":
            "Display two tappable buttons for a binary yes/no question.",
        "parameters": {
          "type": "object",
          "properties": {
            "question": {"type": "string"},
            "yes_label": {"type": "string"},
            "no_label": {"type": "string"}
          },
          "required": ["question"],
          "additionalProperties": false
        }
      }
    },
    {
      "type": "function",
      "function": {
        "name": "show_info",
        "description":
            "Display information visually without requiring any user action. Resolves immediately.",
        "parameters": {
          "type": "object",
          "properties": {
            "title": {"type": "string"},
            "content": {"type": "string"},
            "items": {
              "type": "array",
              "items": {
                "type": "object",
                "properties": {
                  "label": {"type": "string"},
                  "value": {"type": "string"}
                },
                "required": ["label", "value"]
              }
            }
          },
          "required": ["title"],
          "additionalProperties": false
        }
      }
    },
    {
      "type": "function",
      "function": {
        "name": "dismiss_tool_ui",
        "description": "Dismiss any currently shown UI immediately.",
        "parameters": {
          "type": "object",
          "properties": {},
          "additionalProperties": false
        }
      }
    },
  ];

  // Voice-agent tools: go in `tools[]` of conversation-init.
  // Uses the web SDK's flat format: { function_name, description, parameters[], required[] }
  static final List<HamsaTool> voiceAgentTools = [
    const HamsaTool(
      functionName: 'show_options',
      description: 'Display a list of options for the user to pick from.',
      parameters: [
        HamsaToolParameter(name: 'title', type: 'string', description: 'Title shown above the options list.'),
        HamsaToolParameter(name: 'options', type: 'string', description: 'JSON-encoded array of options. Each item: { id: string, label: string, description?: string }.'),
        HamsaToolParameter(name: 'subtitle', type: 'string', description: 'Optional subtitle text.'),
        HamsaToolParameter(name: 'initial_selected_id', type: 'string', description: 'ID of the initially selected option.'),
      ],
      required: ['title', 'options'],
    ),
    const HamsaTool(
      functionName: 'confirm_data',
      description: 'Show the user data you collected so they can verify and optionally edit it before confirming.',
      parameters: [
        HamsaToolParameter(name: 'fields', type: 'string', description: 'JSON-encoded array of fields. Each item: { key: string, label: string, value: string }.'),
        HamsaToolParameter(name: 'title', type: 'string', description: 'Title shown above the data fields.'),
      ],
      required: ['fields'],
    ),
    const HamsaTool(
      functionName: 'show_summary',
      description: 'Display a read-only summary of collected information.',
      parameters: [
        HamsaToolParameter(name: 'fields', type: 'string', description: 'JSON-encoded array of fields. Each item: { key: string, label: string, value: string }.'),
        HamsaToolParameter(name: 'title', type: 'string', description: 'Title shown above the summary.'),
      ],
      required: ['fields'],
    ),
    const HamsaTool(
      functionName: 'enter_number',
      description: 'Show a numeric keypad for the user to enter a number.',
      parameters: [
        HamsaToolParameter(name: 'title', type: 'string', description: 'Title shown above the keypad.'),
        HamsaToolParameter(name: 'subtitle', type: 'string', description: 'Optional subtitle text.'),
        HamsaToolParameter(name: 'max_length', type: 'string', description: 'Maximum number of digits allowed.'),
        HamsaToolParameter(name: 'initial_value', type: 'string', description: 'Pre-filled value.'),
      ],
      required: ['title'],
    ),
    const HamsaTool(
      functionName: 'enter_text',
      description: 'Show a text input field for the user to type free-form text.',
      parameters: [
        HamsaToolParameter(name: 'title', type: 'string', description: 'Title shown above the text field.'),
        HamsaToolParameter(name: 'subtitle', type: 'string', description: 'Optional subtitle text.'),
        HamsaToolParameter(name: 'placeholder', type: 'string', description: 'Placeholder hint text.'),
        HamsaToolParameter(name: 'max_length', type: 'string', description: 'Maximum character length.'),
        HamsaToolParameter(name: 'initial_value', type: 'string', description: 'Pre-filled value.'),
        HamsaToolParameter(name: 'input_type', type: 'string', description: 'Input type: text, email, or tel.'),
      ],
      required: ['title'],
    ),
    const HamsaTool(
      functionName: 'pick_date',
      description: 'Show a date picker for the user to select a date.',
      parameters: [
        HamsaToolParameter(name: 'title', type: 'string', description: 'Title shown above the date picker.'),
        HamsaToolParameter(name: 'subtitle', type: 'string', description: 'Optional subtitle text.'),
        HamsaToolParameter(name: 'initial_value', type: 'string', description: 'Pre-selected date (ISO format).'),
        HamsaToolParameter(name: 'min_date', type: 'string', description: 'Earliest selectable date (ISO format).'),
        HamsaToolParameter(name: 'max_date', type: 'string', description: 'Latest selectable date (ISO format).'),
      ],
      required: ['title'],
    ),
    const HamsaTool(
      functionName: 'ask_yes_no',
      description: 'Ask the user a yes/no question and display two tappable buttons.',
      parameters: [
        HamsaToolParameter(name: 'question', type: 'string', description: 'The yes/no question to display.'),
        HamsaToolParameter(name: 'yes_label', type: 'string', description: 'Label for the yes button.'),
        HamsaToolParameter(name: 'no_label', type: 'string', description: 'Label for the no button.'),
      ],
      required: ['question'],
    ),
    const HamsaTool(
      functionName: 'show_info',
      description: 'Display information visually without requiring any user action. Resolves immediately.',
      parameters: [
        HamsaToolParameter(name: 'title', type: 'string', description: 'Title of the info card.'),
        HamsaToolParameter(name: 'content', type: 'string', description: 'Body text content.'),
        HamsaToolParameter(name: 'items', type: 'string', description: 'Optional JSON-encoded array of key-value rows.'),
      ],
      required: ['title'],
    ),
    const HamsaTool(
      functionName: 'dismiss_tool_ui',
      description: 'Dismiss any currently rendered interactive tool UI immediately.',
    ),
    const HamsaTool(
      functionName: 'prefill_active_tool',
      description: 'Update the pre-filled value in the currently visible tool overlay without dismissing it.',
      parameters: [
        HamsaToolParameter(name: 'value', type: 'string', description: 'New pre-filled value.'),
        HamsaToolParameter(name: 'selected_id', type: 'string', description: 'New pre-selected option ID.'),
      ],
    ),
  ];
}
