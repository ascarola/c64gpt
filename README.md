# C64GPT

**C64GPT** is an AI *simulation* for the **Commodore 64**, written entirely in **6502 assembly language**.
It demonstrates how far the *illusion of intelligence* can be pushed on 8-bit hardware using deterministic techniques such as scored keyword matching, response pools, lightweight conversational state, and contextual word echoing — all within the constraints of a 1982 home computer.

This is **not** a neural network and does **not** require external hardware, cloud services, or a modern computer.
C64GPT runs locally on a real Commodore 64 (or emulator) using only its built-in CPU and RAM.

---

## What C64GPT Is (and Isn't)

**C64GPT is:**
- A conversational system inspired by the *behavior* of modern LLMs
- A demonstration of context, follow-ups, and adaptive responses on 8-bit hardware
- A fully local, deterministic program written in 6502 assembly
- A retro-computing and software-design experiment

**C64GPT is not:**
- A neural network
- A generative language model
- Connected to the internet
- Calling ChatGPT or any external API

---

## How It Works

C64GPT focuses on *behavioral realism*, not statistical generation. Key techniques include:

- **Scored keyword matching** — ~100 keywords are scanned and scored by weight, topic continuity, and conversation mode. The best match wins, not the first match.

- **Response pools** — 11 pools (greetings, humor, C64 hardware, SID, sprites, thanks, help, and more) with cycling indices to eliminate repetition.

- **Negation detection** — "I don't like sprites" won't trigger an enthusiastic sprite response. The engine scans for "not", "don't", "hate", and "no" before keyword matches and skips negated keywords.

- **Name learning** — Say "my name is Tony" and C64GPT remembers your name, using it in later responses with proper mixed-case display.

- **Conversation stats** — Ask "how many questions have I asked?" and C64GPT reports the turn count dynamically, with flavor text based on conversation length.

- **Topic depth** — After discussing a topic, say "tell me more" or "go on" and C64GPT provides a deeper follow-up: VIC-II timing details, 6502 optimization tips, the Chinese Room argument, and more.

- **Time-aware greetings** — Set the clock with "the time is 3:00 PM" and subsequent hellos get "Good afternoon!" prepended automatically.

- **Input length awareness** — Short inputs get snappy responses. Long, detailed questions receive acknowledgment: "That's a thoughtful question."

- **Word echo / template responses** — Key words from user input are reflected back in replies, creating the illusion of understanding and context.

- **Conversation modes** — Switch between normal, concise, technical, and playful tones with commands like "be funny" or "be technical".

- **Follow-up prompts** — Certain responses trigger clarifying questions. Short answers like "yes", "no", or "ok" get appropriate continuations.

- **Date and time system** — Set today's date ("today is February 7, 2026") and the current time. C64GPT reads the CIA1 TOD clock for time-aware responses.

- **Turn milestones** — Bonus remarks at turns 5, 10, and 20 create a sense of shared conversational history.

- **Intent detection** — Input is classified as question, statement, greeting, request, or follow-up. Every 3rd question/request gets a conversational aside like "Does that help?"

All of this is done deterministically, with no probabilistic models or external dependencies.

---

## Project Size

| Component | Size |
|-----------|------|
| Source (`.asm`) | ~5,000 lines / ~104 KB |
| Assembled PRG | ~19 KB |
| RAM buffers | ~360 bytes ($C000-$C160) |
| Zero page usage | $02-$0F (state), $FB-$FE (pointers) |

Plenty of room remains for future expansion while staying well within C64 limits.

---

## Screen Layout

```
Row  0   [      C64GPT v0.2 - AI ASSISTANT       ]  (cyan, reverse)
Row  1   ----------------------------------------   (dark grey separator)
Rows 2-21   Chat area (scrolling)                    (mixed colors)
Row 22   ----------------------------------------   (dark grey separator)
Rows 23-24   > User input (2 lines, 76 chars max)   (light green)
```

- **Cyan**: AI label ("C64GPT:")
- **Light grey**: AI responses (typewriter effect)
- **Light green**: User input
- **Yellow**: Follow-up prompts
- **Dark grey**: Milestones and asides

---

## Requirements

- Commodore 64 hardware **or**
- Emulator such as [VICE](https://vice-emu.sourceforge.io/)
- 1541 disk image or PRG loader

---

## Running C64GPT

On real hardware or emulator:
```
LOAD "C64GPT",8,1
RUN
```

---

## Building from Source

Most users **do not need to build** C64GPT themselves.
A preassembled `c64gpt.prg` is provided.

If you want to assemble from source:

- Assembler: [ACME](https://sourceforge.net/projects/acme-crossass/)

```
acme -v c64gpt.asm
```

This produces `c64gpt.prg` directly (output file and format are configured in the source).

---

## Things to Try

**Basics**
- `hello` / `who are you` / `help`
- `tell me a joke`
- `what can you do?`

**C64 Hardware**
- `tell me about sprites`
- `what is the SID chip?`
- `how much RAM do you have?`

**Conversation Modes**
- `be funny` then ask anything
- `be technical` then `tell me about the 6502`
- `be normal` to reset

**Name Learning**
- `my name is Tony` — then keep chatting

**Negation**
- `I don't like sprites` vs. `I love sprites`

**Topic Depth**
- Ask about a topic, then say `tell me more` or `go on`

**Time Awareness**
- `the time is 8:30 AM` then `hello` — "Good morning!"

**Date System**
- `today is February 7, 2026` then `what day is it?`

**Stats**
- `how many questions have I asked?`

**Long Input**
- Type a detailed question (40+ characters) and notice the acknowledgment

**Philosophy**
- `are you alive?` / `are you sentient?`
- `what is the meaning of life?`

---

## Architecture Overview

```
User Input
    |
    v
[make_lowercase] --> MATCH_BUF
[capture_word]   --> WORD_BUF
[detect_intent]  --> intent classification
    |
    v
[check_mode_switch]     --> mode change? done
[check_followup]        --> "tell me more" / yes/no? done
[check_stats_query]     --> stats request? done
[check_datetime]        --> date/time command? done
[check_name_learning]   --> name detected? done
[score_response]        --> keyword scan + negation check
    |                       score by weight + topic + mode
    |                       resolve pool or direct response
    v
[display_ai_msg]        --> typewriter effect output
[maybe_followup_prompt] --> clarifying question?
[post_intent_add]       --> "Does that help?" aside
[check_milestone]       --> turn 5/10/20 remark
```

---

## Design Philosophy

C64GPT is built around a simple idea:

> **Intelligence is often inferred from behavior, not computation.**

By carefully modeling how modern AI systems *respond* — rather than how they *compute* — C64GPT demonstrates that conversational realism can emerge even on extremely limited hardware.

This project intentionally avoids shortcuts such as external processors, serial bridges, or cloud APIs to preserve historical and technical authenticity.

---

## Project Status

C64GPT is actively evolving. Current version: **v0.2+**

**Implemented:**
- Scored keyword matching (~100 keywords, weighted, topic-aware)
- 11 response pools with cycling indices
- Negation detection (skips negated keyword matches)
- Name learning with proper PETSCII case display
- Conversation stats (dynamic turn count reporting)
- Topic depth system (7 deeper responses by topic)
- Time-aware greetings (morning/afternoon/evening via CIA1 TOD)
- Input length awareness (short/medium/long classification)
- Word echo templates ($01 for captured word, $02 for user name)
- 4 conversation modes (normal/concise/technical/playful)
- Date and time system with natural language parsing
- Follow-up prompts and continuation handling
- Enhanced intent detection (5 categories)
- Post-intent conversational asides
- Turn milestones
- Custom scrolling chat area with color RAM preservation
- Typewriter effect on AI responses
- Two-line input (76 characters max)

---

## Contributing

Contributions are welcome, especially in:
- 6502 optimization
- Conversational design and new response content
- Retro UI/UX improvements
- Testing on real hardware
- Documentation and demos

Please keep all additions consistent with the project's core principle:
**everything must run locally on a stock Commodore 64.**

---

## License

MIT License.
See `LICENSE` for details.

---

## Acknowledgments

Inspired by:
- The Commodore 64 demo scene
- Early chatbots (ELIZA, SHRDLU)
- Modern LLM conversational patterns
- The enduring creativity of the retro-computing community

---

## Why This Exists

Because it's fun.
Because it's weird.
Because it shows what thoughtful software design can do — even at 1.023 MHz.
