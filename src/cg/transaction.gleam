import cg/date.{type Date}

pub type Kind {
  Buy
  Sale
}

pub type Transaction {
  Transaction(
    asset: String,
    date: Date,
    id: String,
    kind: Kind,
    // Before fee
    price_each: Float,
    // Total fee for transaction
    fee: Float,
    qty: Float,
    allocated: Float,
  )
}
