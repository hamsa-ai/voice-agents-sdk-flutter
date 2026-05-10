// ignore_for_file: prefer_single_quotes
import 'dart:convert';
import 'models.dart';

/// Static definitions for the render-engine interactive tool protocol.
/// These are sent verbatim in the conversation-init call when
/// [HamsaVoiceAgent.start] is called with interactiveAgent = true.
///
/// Kept in sync with the web SDK:
///   src/features/publish/constants/render-engine.constants.ts
class RenderEngineConstants {
  RenderEngineConstants._();

  /// Pre-encoded JSON string for the `render-agent-tools` /
  /// `render-engine-tools` param — sent in conversation-init params.
  /// Uses OpenAI function-calling format (type/function/name/parameters).
  static final String toolsJson = jsonEncode(_toolDefinitions);

  /// System prompt string for the `render-agent-system-prompt` /
  /// `render-engine-system-prompt` param.
  static const String systemPrompt = r'''
You are an interactive UI rendering assistant for a real-time voice conversation interface.

Your sole job is to decide — based on the conversation transcript — whether any interactive UI should be displayed on the user's screen RIGHT NOW to complement or assist what the voice agent just said.

## Understanding the context you receive

The conversation history contains messages of three kinds:

1. **Knowledge base context** — assistant messages starting with "Additional information relevant to the user's next message:". These contain structured data retrieved from a knowledge base (product details, contact info, stats, etc.).

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
Look at the tool_calls in the conversation history. If the most recent tool call showed the same UI for the same question and the user hasn't responded yet, do NOT show it again. If the topic changed or the agent is asking something new, update accordingly.

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
| show_paths | the agent is at a flow branching point with named next-steps; renders persistent pill buttons below the orb that stay visible even while the agent speaks — call whenever entering a node with outgoing paths; replace by calling show_paths again with new paths |
| dismiss_tool_ui | the user answered by voice first, the topic changed, or on-screen UI must clear immediately |

## Tool arguments and results (client contract)

Follow the function JSON schema you were given. The client renders **full overlays** (lists, forms, keypad, date picker, yes/no) and blocks the voice pipeline until each call completes, times out (120s), is dismissed, or returns a validation error.

- **show_options** — Required: `title`, `options` (array of `{ id, label, description? }`). Optional: `subtitle`, `initial_selected_id`. Success: `{ "selected_id": "<id>", "selected_label": "<label>" }`. Dismiss/timeout: `{ "dismissed": true }` / `{ "timed_out": true }`. Bad JSON/shape: `{ "error": "..." }`.

- **confirm_data** — Required: `fields` (array of `{ key, label, value, type?: "text"|"date" }`). Optional: `title`. Success: `{ "confirmed": true|false, "fields": [...] }` (values may be edited in UI). When `confirmed: false`, the voice agent is told which field the user wants to correct — ask the user which field to update.

- **show_summary** — Same `fields` / `title` shape as confirm but read-only. Completes with `{ "dismissed": true }` (or timeout).

- **enter_number** — Required: `title`. Optional: `subtitle`, `max_length` (1–50, default 12), `initial_value` (digits). Success: `{ "value": "<digits>" }`.

- **enter_text** — Required: `title`. Optional: `subtitle`, `placeholder`, `max_length` (1–500, default 200), `initial_value`, `input_type` (`text`|`email`|`tel`). Success: `{ "value": "<text>" }`.

- **pick_date** — Required: `title`. Optional: `subtitle`, `initial_value`, `min_date`, `max_date` (dates `YYYY-MM-DD`). Success: `{ "value": "YYYY-MM-DD" }`.

- **ask_yes_no** — Required: `question`. Optional: `yes_label`, `no_label`. Success: `{ "answer": "yes" }` or `{ "answer": "no" }`.

- **show_info** — Required: `title`. Optional: `content` (paragraph), `items` (array of `{ label, value }`). Returns immediately with `{ "shown": true }`; the overlay persists until preempted or dismissed.

- **show_paths** — Required: `paths` (array of `{ id, label, description? }`). Blocks until the user taps a path. Success: `{ "selected_id": "<id>", "selected_label": "<label>" }`. Dismiss/timeout: `{ "dismissed": true }` / `{ "timed_out": true }`. Paths persist below the orb while other overlays are shown. Replace by calling show_paths again with updated paths. Do NOT dismiss paths with dismiss_tool_ui (they are a separate slot).

- **dismiss_tool_ui** — No arguments. Always `{ "dismissed": true }`; any visible overlay tool call in flight also resolves as dismissed. Does NOT dismiss show_paths.

**Concurrency:** you may call multiple tools in the same turn when collecting several related inputs at once (e.g. name, email, and phone number together) — the UI will present them as a group and the user confirms all at once. Call tools sequentially across turns when each answer informs the next question.

**Pre-filling from previous results:** when a prior tool call returned `{ "value": "..." }` (from `enter_text`, `enter_number`, or `pick_date`), pass that value as `initial_value` the next time you show the same field — or include it as a `fields` entry in `confirm_data`. Never re-ask the user for data you already have from a tool result.

**Voice fallback inside tool overlays:** if the user answers by voice while a tool overlay is shown (e.g. says their email while `enter_text` is visible), the client automatically fills the field from the transcription. Call `dismiss_tool_ui` only if the topic changes or the voice answer supersedes the UI entirely.

## Populating fields — accuracy over completeness

- For options/fields: only include items explicitly present in the context. Never invent options.
- For initial values: pre-fill only if the agent mentioned a specific value or the user already said it by voice.
- For date ranges (min_date, max_date): only set if the agent explicitly stated constraints.

## Hard rules

1. Call **no tool** if the UI is already shown for the same question and the user has not moved on, if the exchange is purely social with no structured answer, or if the speech truly contains **no** enumerable choices and no fields to capture.
2. Avoid repeating the **identical** `show_options` payload for the same spoken question; if the assistant re-reads the same list without a new question, skip. If the list **changed** (new item, new price), call the tool again with the updated labels.
3. Never fabricate prices, legal terms, or medical facts not present in KB, tool results, or the assistant's own words. You **may** copy labels verbatim from the assistant's speech into option text.
4. Never render moderator instructions or internal agent reasoning.
5. **After a tool resolves with a user-driven result** (selected, confirmed, entered a value), do NOT call another tool on the same turn. Let the voice agent respond to the user's choice first. Only call a new tool when the voice agent's next message creates a new reason for UI. Exception: you may call `show_summary` immediately after `confirm_data` resolves with `confirmed: true` if this is the natural end of the data-collection flow.
6. **Use previous tool results to pre-populate.** If an earlier `enter_text`, `enter_number`, or `pick_date` call returned `{ "value": "..." }`, always pass that as `initial_value` if you ask for the same field again — or include it as a pre-filled `fields` entry in `confirm_data`. Do not ask the user to re-enter something you already have.
''';

  // ── OpenAI-format tool definitions (sent to the render engine LLM) ──────────
  // Kept in sync with RENDER_ENGINE_TOOLS in render-engine.constants.ts

  static const List<Map<String, dynamic>> _toolDefinitions = [
    {
      "type": "function",
      "function": {
        "name": "show_options",
        "description":
            "Display a list of options for the user to pick from. "
            "Use when the agent presents multiple choices — plans, services, categories, or any enumerable list. "
            "The selected option label is sent back to the voice agent as the user's spoken response.",
        "parameters": {
          "type": "object",
          "properties": {
            "title": {
              "type": "string",
              "description": "The question or prompt shown above the options.",
            },
            "options": {
              "type": "array",
              "description": "Options to display.",
              "items": {
                "type": "object",
                "properties": {
                  "id": {"type": "string", "description": "Unique identifier for this option."},
                  "label": {"type": "string", "description": "Display text shown to the user."},
                  "description": {"type": "string", "description": "Optional subtitle or detail for this option."},
                },
                "required": ["id", "label"],
              },
            },
            "subtitle": {
              "type": "string",
              "description": "Optional secondary line shown below the title.",
            },
            "initial_selected_id": {
              "type": "string",
              "description": "Pre-select this option by id. Use when the user already indicated a choice by voice.",
            },
          },
          "required": ["title", "options"],
          "additionalProperties": false,
        },
      },
    },
    {
      "type": "function",
      "function": {
        "name": "confirm_data",
        "description":
            "Show collected data to the user for verification before proceeding. "
            "Use when the agent has gathered structured information (name, date, address, etc.) "
            "and needs the user to confirm or correct it.",
        "parameters": {
          "type": "object",
          "properties": {
            "fields": {
              "type": "array",
              "description": "Data fields to display for review.",
              "items": {
                "type": "object",
                "properties": {
                  "key": {"type": "string", "description": "Internal field identifier."},
                  "label": {"type": "string", "description": "Human-readable field name, e.g. \"Full name\"."},
                  "value": {"type": "string", "description": "Current value to display."},
                  "type": {
                    "type": "string",
                    "enum": ["text", "date"],
                    "description": "Field type — \"date\" renders an inline date picker for editing.",
                  },
                },
                "required": ["key", "label", "value"],
              },
            },
            "title": {
              "type": "string",
              "description": "Optional heading. Defaults to \"Is this correct?\".",
            },
          },
          "required": ["fields"],
          "additionalProperties": false,
        },
      },
    },
    {
      "type": "function",
      "function": {
        "name": "show_summary",
        "description":
            "Display a read-only summary of collected or processed information. "
            "Use at the end of a flow to recap what was gathered. "
            "The user taps \"Got it\" to dismiss.",
        "parameters": {
          "type": "object",
          "properties": {
            "fields": {
              "type": "array",
              "description": "Summary fields to display.",
              "items": {
                "type": "object",
                "properties": {
                  "key": {"type": "string"},
                  "label": {"type": "string"},
                  "value": {"type": "string"},
                  "type": {
                    "type": "string",
                    "enum": ["text", "date"],
                    "description": "Optional display hint (same as confirm_data).",
                  },
                },
                "required": ["key", "label", "value"],
              },
            },
            "title": {
              "type": "string",
              "description": "Optional heading. Defaults to \"Here's a summary\".",
            },
          },
          "required": ["fields"],
          "additionalProperties": false,
        },
      },
    },
    {
      "type": "function",
      "function": {
        "name": "enter_number",
        "description":
            "Prompt the user to provide a numeric value (ID, PIN, phone, reference code, etc.). "
            "Shows a numeric keypad until the user confirms. "
            "The user may still answer by voice on the client; the tool result is the confirmed digit string.",
        "parameters": {
          "type": "object",
          "properties": {
            "title": {"type": "string", "description": "The prompt shown above the keypad."},
            "subtitle": {"type": "string", "description": "Optional hint text shown below the title."},
            "max_length": {
              "type": "integer",
              "description": "Maximum digits allowed (1–50). Default: 12.",
            },
            "initial_value": {
              "type": "string",
              "description": "Pre-fill the keypad with this value (digits only).",
            },
          },
          "required": ["title"],
          "additionalProperties": false,
        },
      },
    },
    {
      "type": "function",
      "function": {
        "name": "enter_text",
        "description":
            "Prompt the user to provide free-form text (email, name, address, reference code, etc.). "
            "Shows a text field until the user confirms. "
            "The user may still answer by voice on the client; the tool result is the confirmed text.",
        "parameters": {
          "type": "object",
          "properties": {
            "title": {"type": "string", "description": "The prompt shown above the input."},
            "subtitle": {"type": "string", "description": "Optional hint text."},
            "placeholder": {
              "type": "string",
              "description": "Placeholder text inside the empty input.",
            },
            "max_length": {
              "type": "integer",
              "description": "Maximum characters allowed (1–500). Default: 200.",
            },
            "initial_value": {
              "type": "string",
              "description": "Pre-fill with this text — useful to let the user verify a voice-transcribed value.",
            },
            "input_type": {
              "type": "string",
              "enum": ["text", "email", "tel"],
              "description": "Keyboard hint for mobile: \"text\" (default), \"email\", or \"tel\".",
            },
          },
          "required": ["title"],
          "additionalProperties": false,
        },
      },
    },
    {
      "type": "function",
      "function": {
        "name": "pick_date",
        "description":
            "Prompt the user to provide a date (birth date, appointment, start date, etc.). "
            "Shows a date picker until the user confirms. "
            "The user may still answer by voice on the client; the tool result is YYYY-MM-DD.",
        "parameters": {
          "type": "object",
          "properties": {
            "title": {"type": "string", "description": "The prompt shown above the date picker."},
            "subtitle": {"type": "string", "description": "Optional hint text."},
            "initial_value": {
              "type": "string",
              "description": "Pre-fill with this date in YYYY-MM-DD format.",
            },
            "min_date": {
              "type": "string",
              "description": "Earliest selectable date in YYYY-MM-DD format.",
            },
            "max_date": {
              "type": "string",
              "description": "Latest selectable date in YYYY-MM-DD format.",
            },
          },
          "required": ["title"],
          "additionalProperties": false,
        },
      },
    },
    {
      "type": "function",
      "function": {
        "name": "ask_yes_no",
        "description":
            "Display two tappable buttons for a binary yes/no question. "
            "Use for simple confirmations where the user would otherwise speak a one-word answer. "
            "The tool result is answer \"yes\" or \"no\" (not free text).",
        "parameters": {
          "type": "object",
          "properties": {
            "question": {"type": "string", "description": "The yes/no question to display."},
            "yes_label": {
              "type": "string",
              "description": "Label for the affirmative button. Default: \"Yes\".",
            },
            "no_label": {
              "type": "string",
              "description": "Label for the negative button. Default: \"No\".",
            },
          },
          "required": ["question"],
          "additionalProperties": false,
        },
      },
    },
    {
      "type": "function",
      "function": {
        "name": "show_info",
        "description":
            "Display information visually without requiring any user action. "
            "Use when the voice agent states a reference number, a fare, a confirmation code, "
            "a list of policy highlights, or any content worth showing on screen. "
            "The overlay stays visible until you call another tool or dismiss_tool_ui. "
            "Resolves immediately — do not wait for the user to respond.",
        "parameters": {
          "type": "object",
          "properties": {
            "title": {"type": "string", "description": "Heading shown at the top of the card."},
            "content": {
              "type": "string",
              "description": "Optional paragraph of body text shown below the title.",
            },
            "items": {
              "type": "array",
              "description": "Optional key-value rows shown below the content.",
              "items": {
                "type": "object",
                "properties": {
                  "label": {"type": "string"},
                  "value": {"type": "string"},
                },
                "required": ["label", "value"],
              },
            },
          },
          "required": ["title"],
          "additionalProperties": false,
        },
      },
    },
    {
      "type": "function",
      "function": {
        "name": "show_paths",
        "description":
            "Display persistent path-selection buttons below the audio visualizer at a flow-agent branching point. "
            "Use when the agent reaches a conversation node where the user must choose one of several named transitions. "
            "Unlike overlay tools, the buttons remain visible continuously — even while the agent is speaking — until "
            "the user taps one, a new show_paths call replaces them, or the call ends. "
            "The selected path label is sent back to the voice agent as the user's spoken intent. "
            "Blocks until the user selects a path.",
        "parameters": {
          "type": "object",
          "properties": {
            "paths": {
              "type": "array",
              "description": "Paths to display.",
              "items": {
                "type": "object",
                "properties": {
                  "id": {"type": "string", "description": "Unique identifier for this path."},
                  "label": {"type": "string", "description": "Display text shown on the button."},
                  "description": {
                    "type": "string",
                    "description": "Optional short description shown next to the label.",
                  },
                },
                "required": ["id", "label"],
              },
            },
          },
          "required": ["paths"],
          "additionalProperties": false,
        },
      },
    },
    {
      "type": "function",
      "function": {
        "name": "dismiss_tool_ui",
        "description":
            "Dismiss any currently shown UI immediately. "
            "Use when the user answered by voice, the topic changed, or the UI is no longer relevant.",
        "parameters": {
          "type": "object",
          "properties": {},
          "additionalProperties": false,
        },
      },
    },
  ];

  // ── Flat-format tool definitions (sent in tools[] of conversation-init) ──────
  // Uses the web SDK's flat format: { function_name, description, parameters[], required[] }
  // Kept in sync with use-render-agent-tools.ts

  static final List<HamsaTool> voiceAgentTools = [
    const HamsaTool(
      functionName: 'show_options',
      description:
          'Display a list of options for the user to pick from. '
          'Use this when you have multiple choices to present — e.g. plans, services, categories. '
          'Pass at most 8 options. If you have more, show the most relevant ones and offer to show more in a follow-up call. '
          'Pass initial_selected_id to pre-highlight an option the user mentioned by voice. '
          'Blocks until the user selects one.',
      parameters: [
        HamsaToolParameter(name: 'title', type: 'string', description: 'The question or prompt shown above the options.'),
        HamsaToolParameter(name: 'options', type: 'string', description: 'JSON-encoded array of options. Each item: { id: string, label: string, description?: string }.'),
        HamsaToolParameter(name: 'subtitle', type: 'string', description: 'Optional secondary line shown below the title.'),
        HamsaToolParameter(name: 'initial_selected_id', type: 'string', description: 'Pre-select this option by its id. Use when the user already indicated a choice by voice and you want them to confirm.'),
      ],
      required: ['title', 'options'],
    ),
    const HamsaTool(
      functionName: 'confirm_data',
      description:
          'Show the user data you collected so they can verify and optionally edit it before confirming.',
      parameters: [
        HamsaToolParameter(name: 'fields', type: 'string', description: 'JSON-encoded array of fields. Each item: { key: string, label: string, value: string, type?: "text"|"date" }.'),
        HamsaToolParameter(name: 'title', type: 'string', description: 'Optional heading. Defaults to "Is this correct?".'),
      ],
      required: ['fields'],
    ),
    const HamsaTool(
      functionName: 'show_summary',
      description:
          'Display a read-only summary of collected or processed information at the end of a flow.',
      parameters: [
        HamsaToolParameter(name: 'fields', type: 'string', description: 'JSON-encoded array of fields. Each item: { key: string, label: string, value: string }.'),
        HamsaToolParameter(name: 'title', type: 'string', description: 'Optional heading. Defaults to "Here\'s a summary".'),
      ],
      required: ['fields'],
    ),
    const HamsaTool(
      functionName: 'enter_number',
      description:
          'Prompt the user to provide a numeric value (ID, PIN, phone, reference code, etc.). '
          'Shows a numeric keypad until the user confirms.',
      parameters: [
        HamsaToolParameter(name: 'title', type: 'string', description: 'The prompt shown above the keypad.'),
        HamsaToolParameter(name: 'subtitle', type: 'string', description: 'Optional hint text shown below the title.'),
        HamsaToolParameter(name: 'max_length', type: 'string', description: 'Maximum digits allowed (1–50). Default: 12.'),
        HamsaToolParameter(name: 'initial_value', type: 'string', description: 'Pre-fill the keypad with this value (digits only).'),
      ],
      required: ['title'],
    ),
    const HamsaTool(
      functionName: 'enter_text',
      description:
          'Prompt the user to provide free-form text (email, name, address, reference code, etc.). '
          'Shows a text field until the user confirms.',
      parameters: [
        HamsaToolParameter(name: 'title', type: 'string', description: 'The prompt shown above the input.'),
        HamsaToolParameter(name: 'subtitle', type: 'string', description: 'Optional hint text.'),
        HamsaToolParameter(name: 'placeholder', type: 'string', description: 'Placeholder text inside the empty input.'),
        HamsaToolParameter(name: 'max_length', type: 'string', description: 'Maximum characters allowed (1–500). Default: 200.'),
        HamsaToolParameter(name: 'initial_value', type: 'string', description: 'Pre-fill with this text — useful to let the user verify a voice-transcribed value.'),
        HamsaToolParameter(name: 'input_type', type: 'string', description: 'Keyboard hint for mobile: "text" (default), "email", or "tel".'),
      ],
      required: ['title'],
    ),
    const HamsaTool(
      functionName: 'pick_date',
      description:
          'Prompt the user to provide a date (birth date, appointment, start date, etc.). '
          'Shows a date picker until the user confirms. The tool result is YYYY-MM-DD.',
      parameters: [
        HamsaToolParameter(name: 'title', type: 'string', description: 'The prompt shown above the date picker.'),
        HamsaToolParameter(name: 'subtitle', type: 'string', description: 'Optional hint text.'),
        HamsaToolParameter(name: 'initial_value', type: 'string', description: 'Pre-fill with this date in YYYY-MM-DD format.'),
        HamsaToolParameter(name: 'min_date', type: 'string', description: 'Earliest selectable date in YYYY-MM-DD format.'),
        HamsaToolParameter(name: 'max_date', type: 'string', description: 'Latest selectable date in YYYY-MM-DD format.'),
      ],
      required: ['title'],
    ),
    const HamsaTool(
      functionName: 'ask_yes_no',
      description:
          'Display two tappable buttons for a binary yes/no question. '
          'The tool result is "yes" or "no".',
      parameters: [
        HamsaToolParameter(name: 'question', type: 'string', description: 'The yes/no question to display.'),
        HamsaToolParameter(name: 'yes_label', type: 'string', description: 'Label for the affirmative button. Default: "Yes".'),
        HamsaToolParameter(name: 'no_label', type: 'string', description: 'Label for the negative button. Default: "No".'),
      ],
      required: ['question'],
    ),
    const HamsaTool(
      functionName: 'show_info',
      description:
          'Display information visually without requiring any user action. '
          'Use when the agent states a reference number, fare, confirmation code, or any content worth showing on screen. '
          'Resolves immediately — the overlay persists until another tool or dismiss_tool_ui is called.',
      parameters: [
        HamsaToolParameter(name: 'title', type: 'string', description: 'Heading shown at the top of the card.'),
        HamsaToolParameter(name: 'content', type: 'string', description: 'Optional paragraph of body text shown below the title.'),
        HamsaToolParameter(name: 'items', type: 'string', description: 'Optional JSON-encoded array of key-value rows (max 8). Each item: { label: string, value: string }.'),
      ],
      required: ['title'],
    ),
    const HamsaTool(
      functionName: 'show_paths',
      description:
          'Display persistent path-selection buttons below the audio visualizer. '
          'Use this at conversation nodes in a flow agent where the user must choose one of several '
          'named transitions (paths). Unlike overlay tools, the buttons remain on screen continuously '
          'until the user taps one, a new show_paths call arrives, or the call ends. '
          'Pass at most 8 paths. Blocks until the user selects a path.',
      parameters: [
        HamsaToolParameter(name: 'paths', type: 'string', description: 'JSON-encoded array of paths. Each item: { id: string, label: string, description?: string }.'),
      ],
      required: ['paths'],
    ),
    const HamsaTool(
      functionName: 'dismiss_tool_ui',
      description:
          'Dismiss any currently rendered interactive tool UI immediately. '
          'Use when the user answered by voice or when you want to continue without tap input. '
          'Does NOT dismiss show_paths.',
    ),
    const HamsaTool(
      functionName: 'prefill_active_tool',
      description: 'Update the pre-filled value in the currently visible tool overlay without dismissing it.',
      parameters: [
        HamsaToolParameter(name: 'value', type: 'string', description: 'New pre-filled value for the active input tool.'),
        HamsaToolParameter(name: 'selected_id', type: 'string', description: 'New pre-selected option ID for the active show_options overlay.'),
      ],
    ),
  ];
}
