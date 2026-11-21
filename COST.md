<!-- SPDX-License-Identifier: MIT -->
# Cost

What the Claude usage that built this port would cost at Anthropic API list prices: **$239.47** over 2026-11-18 to 2026-11-21 (3,094 model replies). Snapshot taken 2026-11-21, during the session that is still running.

This is an API-equivalent figure. Work done on a Claude subscription is not billed per token, so treat it as the size of the work, not an invoice. It covers this repository only (not the sibling Pixel 2 project) and nothing outside Claude (hardware, electricity, the owner's time).

## By day

| Day | Model | Who | Replies | Cost |
|---|---|---|---:|---:|
| 2026-11-18 | Opus 5.5 | main | 12 | $1.70 |
| 2026-11-18 | Opus 5.5 | subagents | 227 | $12.52 |
| 2026-11-19 | Opus 5.5 | main | 882 | $63.11 |
| 2026-11-19 | Opus 5.5 | subagents | 260 | $15.22 |
| 2026-11-20 | Fable 5.2 | subagents | 52 | $7.81 |
| 2026-11-20 | Opus 5.5 | main | 789 | $67.41 |
| 2026-11-21 | Opus 5.5 | main | 842 | $70.62 |
| 2026-11-21 | Opus 5.5 | subagents | 30 | $1.09 |
| **Total** | | | **3,094** | **$239.47** |

Per day: 2026-11-18 $14.22, 2026-11-19 $78.33, 2026-11-20 $75.22, 2026-11-21 $71.70.

## Where the money went

| Kind | Tokens | Cost | Share |
|---|---:|---:|---:|
| Cache reads (the conversation re-read each turn) | 619.6 M | $123.93 | 52 % |
| Cache writes (5 min and 1 h) | 8.1 M | $60.45 | 25 % |
| Output (replies, tool calls, thinking) | 2.7 M | $55.07 | 23 % |
| Uncached input | 0.0 M | $0.03 | 0 % |

Cache reads dominate: every turn of a long session re-reads the whole context (619.6 M tokens in total), cheap per token ($0.20/M) but large in volume. Subagents (research, the privacy audit) cost $36.63 of the total.

## Method

- Source: Claude Code's local session logs for this repository (both clone locations), assistant messages only, each counted once by message id; subagent logs included.
- Prices per million tokens (Anthropic list prices, November 2026):

| Model | Input | Cache write 5 min | Cache write 1 h | Cache read | Output |
|---|---:|---:|---:|---:|---:|
| Opus 5.5 | $4 | $5 | $8 | $0.20 | $20 |
| Fable 5.2 | $8 | $10 | $16 | $0.20 | $40 |

- Cache writes are split into 5-minute and 1-hour writes from each reply's usage record (1.25x and 2x the input price).
- Not included: replies with no usage record, and anything after the snapshot.
