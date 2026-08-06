import cg/date.{type Date}
import youid/uuid

pub type Allocation {
  Allocation(
    buy_date: Date,
    buy_price_each: Float,
    buy_transaction_id: String,
    capital_gain: Float,
    asset: String,
    days_held: Int,
    id: uuid.Uuid,
    qty: Float,
    sale_date: Date,
    sale_price_each: Float,
    sale_transaction_id: String,
  )
}
