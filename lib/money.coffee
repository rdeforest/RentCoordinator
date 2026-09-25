# Money, to the cent.
#
# Amounts are stored and sent as dollars, and every stored amount is a whole
# number of cents (recordEvent refuses anything else). Arithmetic happens in
# integer cents: the rent math multiplies fractional hours by an hourly rate,
# and doing that in float dollars produced months owing $1,433.3333333333333,
# which no payment can settle (bug 35). Convert on the way in, compute, and
# convert back on the way out.
#
# Cents are computed through Math.round on a scaled value rather than toFixed,
# which is locale- and precision-sensitive.

# `?` and not `or`: only a missing value defaults. `or` treats NaN as falsy
# too, which turned a corrupt amount into $0.00 and reported the month PAID.
cents = (dollars) -> Math.round (dollars ? 0) * 100

# For values read out of the ledger. No default: a missing amount stays NaN,
# so the month it belongs to is reported corrupt rather than as $0.
centsOf = (dollars) -> Math.round dollars * 100

fromCents = (c) -> c / 100

# The nearest real amount of money. Idempotent.
dollars = (amount) -> fromCents cents amount

same = (a, b) -> cents(a) is cents(b)

isWholeCents = (dollars) ->
  Number.isFinite(dollars) and Math.abs(dollars * 100 - Math.round(dollars * 100)) < 1e-6

module.exports = { cents, centsOf, fromCents, dollars, same, isWholeCents }
