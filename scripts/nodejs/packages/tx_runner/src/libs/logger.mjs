import log from 'npmlog'

log.prefixStyle = { fg: 'brightYellow' }
log.addLevel('debug', 1000, { fg: 'yellow', bg: 'black' }, 'DBUG')
log.addLevel('verbose', 2000, { fg: 'cyan', bg: 'black' }, 'VERB')
log.addLevel('info', 3000, { fg: 'green', bold: true }, 'INFO')
log.addLevel('warn', 4000, { fg: 'black', bg: 'yellow', bold: true }, 'WARN')
log.addLevel('error', 5000, { fg: 'red', bg: 'black', bold: true }, 'ERR!')


const getNow = () => {
    const now = new Date();
    return now.toLocaleTimeString()
}

export class Logger {

    static setLevel(level) {
        log.level = level
    }

    static debug(...args) {
        log.heading = `[${getNow()}]`
        log.debug(...args)
    }

    static verbose(...args) {
        log.heading = `[${getNow()}]`
        log.verbose(...args)
    }

    static info(...args) {
        log.heading = `[${getNow()}]`
        log.info(...args)
    }

    static warn(...args) {
        log.heading = `[${getNow()}]`
        log.warn(...args)
    }

    static error(...args) {
        log.heading = `[${getNow()}]`
        log.error(...args)
    }
}

