# Money, to the cent.
#
# Dollars are held as JavaScript numbers throughout this app, which is fine
# for values that land on a cent and wrong for values that do not. The rent
# math produces the latter routinely: 200 minutes of work at $50/hour is a
# credit of $166.666…, leaving a month owing $1,433.3333333333333.
#
# Nobody can pay that. Stripe charges integer cents, so the tenant pays
# $1,433.33, the month is left owing a third of a cent, and it reads PARTIAL
# for ever — a paid month the dashboard will not stop asking about.
#
# Rounding at the boundary where a number becomes an amount of money keeps
# every derived value payable and every comparison exact. Cents are computed
# through Math.round on a scaled integer rather than toFixed, which is
# locale- and precision-sensitive.

# `?` and not `or`: only a missing value defaults. `or` treats NaN as falsy
# too, which turned a corrupt amount into $0.00 and reported the month PAID —
# erasing the corruption in the one direction that says nothing is owed.
cents = (dollars) -> Math.round (dollars ? 0) * 100

# The nearest real amount of money. Idempotent: rounding an already-round
# value changes nothing.
dollars = (amount) -> cents(amount) / 100

# True when two amounts are the same money, regardless of float residue.
same = (a, b) -> cents(a) is cents(b)

# a - b, to the cent. The subtraction that was leaving thirds of a cent behind.
minus = (a, b) -> (cents(a) - cents(b)) / 100

module.exports = { cents, dollars, same, minus }
