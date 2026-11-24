// herdr-keep-warm: while a session sits idle in a herdr-core terminal whose
// "Keep cache warm" switch is on (the agent.keep_warm label, set from the
// workbench's pane header), asks a one-word question over the conversation
// every 25 minutes. The question is a fork: it reads the conversation's prompt
// cache, which renews it, and neither joins the conversation nor touches the
// terminal.
//
// It reports through the terminal's labels, as lib/warm.js reads them:
// agent.warm_state=refreshing while a ping runs, and agent.warm_failed=<epoch>
// when it stops pinging, because a ping found the cache gone or two got no
// answer. The session's next turn starts it again. Every ping is also logged,
// with its verdict and token counts, to LOG_FILE under the home directory.
//
// Outside a herdr-core terminal it does nothing.
import type { Register } from 'claude-code'
import { LOG_FILE, PROMPT, isTime, labelsOf, logLine, verdict, wants } from './logic.js'

export const register: Register = on => {
  let lastActivityAt = 0
  let isBusy = false
  let hasStopped = false
  let failures = 0
  // Set once a session in a herdr-core terminal starts: clears the failure
  // label after a turn.
  let reset: (() => Promise<void>) | undefined

  on('session.start', async ($, e, next) => {
    const terminal = await $.env.get('HC_TERMINAL_ID')

    if (!e.isInteractive || terminal === undefined || terminal === '') return next(e)

    const hc = async (...args: string[]) => {
      try {
        return await $.process.run(['hc', ...args], { timeoutMs: 10_000 })
      } catch {
        return undefined
      }
    }

    const logFile = `${await $.env.get('HOME')}/${LOG_FILE}`

    // An append, not $.fs.write's whole-file write: every session on the
    // machine logs to the same file.
    const log = async (line: string) => {
      try {
        await $.process.run(['sh', '-c', 'mkdir -p "${1%/*}" && cat >> "$1"', 'sh', logFile], { stdin: line, timeoutMs: 10_000 })
      } catch {}
    }

    // Not only when hasStopped: the label outlives the session that set it
    // (a restart, a resume after a reboot), and this one never stopped.
    reset = async () => {
      await hc('label', terminal, 'agent.warm_failed=')
      hasStopped = false
      failures = 0
    }
    await reset()
    lastActivityAt = await $.clock.now()

    $.clock.every(30_000, async () => {
      const now = await $.clock.now()

      if (isBusy || hasStopped || !isTime(lastActivityAt, now)) return

      const read = await hc('get', terminal, '--json')
      const labels = read?.exitCode === 0 ? labelsOf(read.stdout) : null

      // isBusy again: a turn may have started while hc ran.
      if (isBusy || wants(labels, now) !== 'yes') return

      isBusy = true
      await hc('label', terminal, 'agent.warm_state=refreshing')

      let reply
      let thrown

      try {
        reply = await $.model.fork({ prompt: PROMPT })
      } catch (error) {
        thrown = error
      }

      const state = verdict(reply)

      if (state === 'warm') failures = 0
      else if (state === 'failed') failures += 1

      const stopped = state === 'cold' || failures >= 2

      if (stopped) {
        hasStopped = true
        await hc('label', terminal, 'agent.warm_state=', `agent.warm_failed=${Math.floor(now / 1000)}`)
      } else {
        await hc('label', terminal, 'agent.warm_state=')
      }

      const session = await $.session.id().catch(() => undefined)
      await log(logLine({ now, terminal, session, reply, thrown, state, stopped }))

      lastActivityAt = await $.clock.now()
      isBusy = false
    })

    return next(e)
  })

  on('prompt.submit', ($, e, next) => {
    isBusy = true

    return next(e)
  })

  on('turn.complete', async ($, e, next) => {
    isBusy = false
    lastActivityAt = await $.clock.now()
    await reset?.()

    return next(e)
  })
}
