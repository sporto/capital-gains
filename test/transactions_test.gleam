import birdie
import gleam/function
import gleeunit
import outcome
import tempo
import tempo/date
import transactions.{type Transaction}

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn fixture_buy(
  asset asset: String,
  date date: tempo.Date,
  fee fee: Float,
  id id: String,
  price buy_price: Float,
  qty buy_qty: Float,
) {
  transactions.make_buy_transaction(
    asset:,
    buy_fee: fee,
    buy_price:,
    buy_qty:,
    date:,
    id:,
  )
}

pub fn fixture_sale(
  asset asset: String,
  date date: tempo.Date,
  fee sale_fee: Float,
  id id: String,
  price sale_price: Float,
  qty sale_qty: Float,
) {
  transactions.make_sale_transaction(
    asset:,
    date:,
    id:,
    sale_price:,
    sale_qty:,
    sale_fee:,
  )
}

pub fn format_amount_test() {
  assert transactions.format_amount(600.1234) == "600.123"
  assert transactions.format_amount(-600.1234) == "-600.123"
}

pub fn parse_date_test() {
  assert transactions.parse_date("1/1/2020") == Ok(date.literal("2020-01-01"))
  assert transactions.parse_date("1/01/2020") == Ok(date.literal("2020-01-01"))
  assert transactions.parse_date("01/01/2020") == Ok(date.literal("2020-01-01"))
}

fn feb_1() {
  date.literal("2020-02-01")
}

fn feb_2() {
  date.literal("2020-02-02")
}

fn feb_4() {
  date.literal("2020-02-04")
}

fn feb_5() {
  date.literal("2020-02-05")
}

fn feb_6() {
  date.literal("2020-02-06")
}

fn assert_report(transactions: List(Transaction), label: String) {
  let transaction_table = transactions.transactions_table(transactions)

  let report = case transactions.report_table(transactions) {
    Ok(report) -> report
    Error(err) -> "Error: " <> outcome.print_line(err, function.identity)
  }

  let output =
    "# "
    <> label
    <> "\n\n## Transactions\n\n"
    <> transaction_table
    <> "\n\n## Allocations\n\n"
    <> report

  output
  |> birdie.snap(label)
}

pub fn transactions_table_has_correct_values_test() {
  let transactions = [
    fixture_buy(
      id: "a",
      date: feb_1(),
      asset: "SOL",
      qty: 100.0,
      price: 10.0,
      fee: 5.0,
    ),
    fixture_sale(
      id: "b",
      date: feb_2(),
      asset: "SOL",
      qty: 50.0,
      price: 10.0,
      fee: 5.0,
    ),
  ]

  let transaction_table = transactions.transactions_table(transactions)

  let output = "\n\n## Transactions\n\n" <> transaction_table

  output
  |> birdie.snap("Transaction table has correct values")
}

pub fn one_sale_has_less_test() {
  [
    fixture_buy(
      id: "a",
      date: feb_1(),
      asset: "XRP",
      qty: 100.0,
      price: 0.5,
      fee: 0.0,
    ),
    fixture_sale(
      id: "b",
      date: feb_2(),
      asset: "XRP",
      qty: 60.0,
      price: 0.6,
      fee: 0.0,
    ),
  ]
  |> assert_report("Simple sale with less")
}

pub fn two_sales_have_less_test() {
  [
    fixture_buy(
      id: "a",
      date: feb_1(),
      asset: "XRP",
      qty: 100.0,
      price: 0.5,
      fee: 0.0,
    ),
    fixture_sale(
      id: "b",
      date: feb_4(),
      asset: "XRP",
      qty: 60.0,
      price: 0.6,
      fee: 0.0,
    ),
    fixture_sale(
      id: "c",
      date: feb_4(),
      asset: "XRP",
      qty: 30.0,
      price: 0.9,
      fee: 0.0,
    ),
  ]
  |> assert_report("Two sales have less")
}

pub fn two_sales_have_exact_test() {
  [
    fixture_buy(
      id: "a",
      date: feb_1(),
      asset: "XRP",
      qty: 100.0,
      price: 0.5,
      fee: 0.0,
    ),
    fixture_sale(
      id: "b",
      date: feb_4(),
      asset: "XRP",
      qty: 60.0,
      price: 0.6,
      fee: 0.0,
    ),
    fixture_sale(
      id: "c",
      date: feb_4(),
      asset: "XRP",
      qty: 40.0,
      price: 0.9,
      fee: 0.0,
    ),
  ]
  |> assert_report("Two sales have exact")
}

pub fn two_sales_have_too_much_test() {
  [
    fixture_buy(
      id: "a",
      date: feb_1(),
      asset: "XRP",
      qty: 100.0,
      price: 0.5,
      fee: 0.0,
    ),
    fixture_sale(
      id: "b",
      date: feb_4(),
      asset: "XRP",
      qty: 60.0,
      price: 0.6,
      fee: 0.0,
    ),
    fixture_sale(
      id: "c",
      date: feb_4(),
      asset: "XRP",
      qty: 50.0,
      price: 0.9,
      fee: 0.0,
    ),
  ]
  |> assert_report("Two sales have too much")
}

pub fn two_buys_one_sale_test() {
  [
    fixture_buy(
      id: "a",
      date: feb_1(),
      asset: "XRP",
      qty: 100.0,
      price: 0.5,
      fee: 0.0,
    ),
    fixture_buy(
      id: "b",
      date: feb_2(),
      asset: "XRP",
      qty: 100.0,
      price: 0.6,
      fee: 0.0,
    ),
    fixture_sale(
      id: "c",
      date: feb_4(),
      asset: "XRP",
      qty: 150.0,
      price: 1.0,
      fee: 0.0,
    ),
  ]
  |> assert_report("Two buys one sale")
}

pub fn two_buys_two_sales_test() {
  [
    fixture_buy(
      id: "a",
      date: feb_1(),
      asset: "XRP",
      qty: 100.0,
      price: 0.5,
      fee: 0.5,
    ),
    fixture_buy(
      id: "b",
      date: feb_2(),
      asset: "XRP",
      qty: 100.0,
      price: 0.5,
      fee: 0.5,
    ),
    fixture_sale(
      id: "c",
      date: feb_4(),
      asset: "XRP",
      qty: 150.0,
      price: 1.0,
      fee: 1.0,
    ),
    fixture_sale(
      id: "d",
      date: feb_5(),
      asset: "XRP",
      qty: 50.0,
      price: 2.0,
      fee: 1.0,
    ),
  ]
  |> assert_report("Two buys, two sales")
}

pub fn order_matters_test() {
  [
    fixture_sale(
      id: "a",
      date: feb_1(),
      asset: "XRP",
      qty: 100.0,
      price: 0.5,
      fee: 0.0,
    ),
    fixture_buy(
      id: "b",
      date: feb_2(),
      asset: "XRP",
      qty: 100.0,
      price: 0.5,
      fee: 0.0,
    ),
  ]
  |> assert_report("Buy must be before")
}

pub fn mixed_test() {
  [
    fixture_buy(
      id: "a",
      date: feb_1(),
      asset: "XRP",
      qty: 100.0,
      price: 0.5,
      fee: 0.5,
    ),
    fixture_buy(
      id: "b",
      date: feb_2(),
      asset: "SOL",
      qty: 100.0,
      price: 50.0,
      fee: 0.5,
    ),
    fixture_sale(
      id: "c",
      date: feb_4(),
      asset: "XRP",
      qty: 50.0,
      price: 0.75,
      fee: 0.5,
    ),
    fixture_buy(
      id: "d",
      date: feb_5(),
      asset: "XRP",
      qty: 100.0,
      price: 0.6,
      fee: 0.5,
    ),
    fixture_sale(
      id: "e",
      date: feb_6(),
      asset: "SOL",
      qty: 50.0,
      price: 40.0,
      fee: 0.5,
    ),
  ]
  |> assert_report("Mixed assets")
}

pub fn duplicate_ids_test() {
  [
    fixture_buy(
      id: "a",
      date: feb_1(),
      asset: "XRP",
      qty: 100.0,
      price: 0.5,
      fee: 0.0,
    ),
    fixture_buy(
      id: "a",
      date: feb_2(),
      asset: "XRP",
      qty: 100.0,
      price: 50.0,
      fee: 0.0,
    ),
  ]
  |> assert_report("Duplicate ids")
}
