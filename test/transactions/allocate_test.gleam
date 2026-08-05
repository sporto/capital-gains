import gleam/list
import tempo/date
import transactions/allocate.{Allocated}
import transactions/transaction.{Buy, Sale, Transaction}
import youid/uuid

fn transaction_fixture() {
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

fn buy_fixture() {
  transaction_fixture()
}

fn sale_fixture() {
  Transaction(..transaction_fixture(), kind: Sale)
}

/// ***************************
/// process_sale_and_buy
/// ***************************
pub fn sale_buy_success_test() {
  let buy = buy_fixture()
  let sale = sale_fixture()

  let actual = allocate.process_sale_and_buy(buy:, sale:)

  let assert Allocated(ubuy, usale, al) = actual

  assert ubuy.allocated == sale.qty
  assert usale.allocated == sale.qty

  assert al.qty == sale.qty
  assert al.buy_transaction_id == buy.id
  assert al.sale_transaction_id == sale.id
  assert al.buy_price_each == buy.price_each
  assert al.sale_price_each == sale.price_each
}

pub fn sale_buy_gains_test() {
  let buy =
    Transaction(
      ..buy_fixture(),
      price_each: 1.0,
      date: date.literal("2020-01-01"),
    )

  let sale =
    Transaction(
      ..sale_fixture(),
      price_each: 2.0,
      date: date.literal("202-01-03"),
    )

  let actual = allocate.process_sale_and_buy(buy:, sale:)

  let assert Allocated(_, _, al) = actual
  assert al.qty == sale.qty
  assert al.days_held == 2
  assert al.capital_gain == 98.0
}

pub fn sale_buy_not_enough_test() {
  let buy = Transaction(..buy_fixture(), qty: 50.0)
  let sale = sale_fixture()

  let actual = allocate.process_sale_and_buy(buy:, sale:)

  let assert Allocated(ubuy, usale, al) = actual

  assert ubuy.allocated == 50.0
  assert usale.allocated == 50.0
  assert al.qty == 50.0
  assert al.buy_transaction_id == buy.id
  assert al.sale_transaction_id == sale.id
}

pub fn sale_buy_consumed_test() {
  let buy = Transaction(..buy_fixture(), allocated: 100.0)
  let sale = sale_fixture()

  let actual = allocate.process_sale_and_buy(buy:, sale:)

  assert actual == allocate.BuyConsumed
}

pub fn sale_buy_bad_dates_test() {
  let buy = Transaction(..buy_fixture(), date: date.literal("2020-02-01"))
  let sale = sale_fixture()

  let actual = allocate.process_sale_and_buy(buy:, sale:)

  assert actual == allocate.ESaleIsEarlier("")
}

/// ***************************
/// process_asset
/// ***************************
pub fn process_test() {
  let buy1 = Transaction(..transaction_fixture(), kind: Buy, qty: 150.0)
  let buy2 = Transaction(..transaction_fixture(), kind: Buy, qty: 50.0)

  let sale1 = Transaction(..transaction_fixture(), kind: Sale, qty: 200.0)

  let ts = [
    //
    buy1,
    buy2,
    sale1,
  ]

  let assert Ok(allocations) = allocate.process(ts)

  assert list.length(allocations) == 2
  assert list.map(allocations, fn(a) { a.qty }) == [150.0, 50.0]
}

pub fn process_multiple_sales_test() {
  let buy1 =
    Transaction(..transaction_fixture(), id: "buy1", kind: Buy, qty: 150.0)

  let sale1 =
    Transaction(..transaction_fixture(), id: "sale1", kind: Sale, qty: 50.0)

  let sale2 =
    Transaction(..transaction_fixture(), id: "sale2", kind: Sale, qty: 100.0)

  let ts = [
    //
    buy1,
    sale1,
    sale2,
  ]

  let assert Ok(allocations) = allocate.process(ts)

  assert list.length(allocations) == 2
  assert list.map(allocations, fn(a) { a.qty }) == [50.0, 100.0]
}

pub fn process_multiple_test() {
  let buy1 = Transaction(..transaction_fixture(), kind: Buy, qty: 150.0)
  let buy2 = Transaction(..transaction_fixture(), kind: Buy, qty: 50.0)

  let sale1 = Transaction(..transaction_fixture(), kind: Sale, qty: 50.0)
  let sale2 = Transaction(..transaction_fixture(), kind: Sale, qty: 150.0)

  let ts = [
    //
    buy1,
    buy2,
    sale1,
    sale2,
  ]

  let assert Ok(allocations) = allocate.process(ts)

  assert list.length(allocations) == 3
  assert list.map(allocations, fn(a) { a.qty }) == [50.0, 100.0, 50.0]
}

pub fn process_buy_insufficient_test() {
  let buy1 = Transaction(..transaction_fixture(), kind: Buy, qty: 50.0)

  let sale1 = Transaction(..transaction_fixture(), kind: Sale, qty: 100.0)

  let ts = [
    //
    buy1,
    sale1,
  ]

  let result = allocate.process(ts)

  assert result == Error("Not enough transactions")
}

pub fn process_not_enough_buys_test() {
  let buy1 = Transaction(..transaction_fixture(), kind: Buy, qty: 50.0)

  let sale1 = Transaction(..transaction_fixture(), kind: Sale, qty: 50.0)
  let sale2 = Transaction(..transaction_fixture(), kind: Sale, qty: 100.0)

  let ts = [
    //
    buy1,
    sale1,
    sale2,
  ]

  let result = allocate.process(ts)

  assert result == Error("Not enough transactions")
}
