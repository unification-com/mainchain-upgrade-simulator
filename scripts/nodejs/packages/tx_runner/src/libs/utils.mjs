export const isIdxOdd = (idx) => {
    return idx % 2
}

export const randomAmountFromBalance = (balanceAmount, minAsPercent = 0.01, maxAsPercent = 0.02) => {
    const balanceInt = parseInt(balanceAmount, 10)

    if(balanceInt === 0) {
        return 0
    }

    const min = Math.floor(balanceInt * minAsPercent)
    const max = Math.floor(balanceInt * maxAsPercent)
    return Math.floor(Math.random() * (max - min + 1)) + min
}
