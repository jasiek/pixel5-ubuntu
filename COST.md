<!-- SPDX-License-Identifier: MIT -->
# Cost

What the Claude usage that built this port would cost at Anthropic API list prices: **$296.50** over 2026-11-18 to 2026-11-22 (3,646 model replies). Snapshot taken 2026-11-22 (after Test 251), during the session that is still running.

This is an API-equivalent figure. Work done on a Claude subscription is not billed per token, so treat it as the size of the work, not an invoice. It covers this repository only (not the sibling Pixel 2 project) and nothing outside Claude (hardware, electricity, the owner's time).

## By day

| Day | Model | Who | Replies | Cost |
|---|---|---|---:|---:|
| 2026-11-18 | Opus 5.5 | main | 12 | $1.70 |
| 2026-11-18 | Opus 5.5 | subagents | 227 | $12.52 |
| 2026-11-19 | Opus 5.5 | main | 882 | $66.43 |
| 2026-11-19 | Opus 5.5 | subagents | 260 | $15.22 |
| 2026-11-20 | Fable 5.2 | subagents | 52 | $7.81 |
| 2026-11-20 | Opus 5.5 | main | 789 | $67.41 |
| 2026-11-21 | Opus 5.5 | main | 981 | $81.40 |
| 2026-11-21 | Opus 5.5 | subagents | 30 | $1.09 |
| 2026-11-22 | Fable 5.2 | subagents | 122 | $17.40 |
| 2026-11-22 | Opus 5.5 | main | 291 | $25.54 |
| **Total** | | | **3,646** | **$296.50** |

Per day (UTC): 2026-11-18 $14.22, 2026-11-19 $81.64, 2026-11-20 $75.22, 2026-11-21 $82.48, 2026-11-22 $42.94.

The 2026-11-19 and 2026-11-21 rows are higher than in the previous snapshot: replies logged after it was taken were counted on the day they happened.

## Where the money went

| Kind | Tokens | Cost | Share |
|---|---:|---:|---:|
| Cache reads (the conversation re-read each turn) | 760.0 M | $152.00 | 51 % |
| Cache writes (5 min and 1 h) | 9.7 M | $74.36 | 25 % |
| Output (replies, tool calls, thinking) | 3.2 M | $70.11 | 24 % |
| Uncached input | 0.0 M | $0.03 | 0 % |

Cache reads dominate: every turn of a long session re-reads the whole context (760.0 M tokens in total), cheap per token ($0.20/M) but large in volume. Subagents (research, the privacy audit, and the Fable agent that found the cause of the encoder hang) cost $54.03 of the total. The video encoder work (Tests 225-251) is most of 2026-11-22.

## Method

- Source: Claude Code's local session logs for this repository (both clone locations), assistant messages only, each counted once by message id; subagent logs included.
- Prices per million tokens (Anthropic list prices, November 2026):

| Model | Input | Cache write 5 min | Cache write 1 h | Cache read | Output |
|---|---:|---:|---:|---:|---:|
| Opus 5.5 | $4 | $5 | $8 | $0.20 | $20 |
| Fable 5.2 | $8 | $10 | $16 | $0.20 | $40 |

- Cache writes are split into 5-minute and 1-hour writes from each reply's usage record (1.25x and 2x the input price).
- Not included: replies with no usage record, and anything after the snapshot.
