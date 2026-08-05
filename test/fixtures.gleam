import tempo/date
import transactions/transaction.{type Transaction, Buy, Sale, Transaction}
import youid/uuid

pub fn fixture_transaction() {
  Transaction(
    asset: "XRP",
    allocated: 0.0,
    date: date.literal("2020-01-01"),
    fee: 1.0,
    id: uuid.v4_string(),
    kind: Buy,
    price_each: 1.0,
    qty: 100.0,
  )
}

pub fn fixture_buy() {
  fixture_transaction()
}

pub fn fixture_sale() {
  Transaction(..fixture_transaction(), kind: Sale)
}

pub fn w_id(transaction: Transaction, id: String) {
  transaction.Transaction(..transaction, id:)
}

pub fn w_date(transaction: Transaction, date) {
  transaction.Transaction(..transaction, date:)
}
