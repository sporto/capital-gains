import argv
import clip.{type Command}
import clip/help
import clip/opt.{type Opt}
import given
import gleam/dict
import gleam/float
import gleam/function
import gleam/int
import gleam/io
import gleam/list
import gleam/result
import gleam/set
import gleam/string
import gsv
import gtabler
import outcome.{type Outcome, outcome}
import simplifile
import tempo.{type Date}
import youid/uuid.{type Uuid}

pub type Kind {
  Buy
  Sale
}

fn kind_to_label(kind: Kind) {
  case kind {
    Buy -> "Buy"
    Sale -> "Sale"
  }
}

fn kind_from_code(code: String) {
  case string.uppercase(code) {
    "BUY" -> Ok(Buy)
    "SALE" -> Ok(Sale)
    _ -> Error("Invalid transaction code " <> code)
  }
}

pub type Transaction {
  TransactionBuy(BuyTransaction)
  TransactionSale(SaleTransaction)
}

fn transaction_id(transaction: Transaction) {
  case transaction {
    TransactionBuy(t) -> t.id
    TransactionSale(t) -> t.id
  }
}

fn transaction_asset(transaction: Transaction) {
  case transaction {
    TransactionBuy(t) -> t.asset
    TransactionSale(t) -> t.asset
  }
}

fn transaction_date(transaction: Transaction) {
  case transaction {
    TransactionBuy(t) -> t.date
    TransactionSale(t) -> t.date
  }
}

fn transaction_kind(transaction: Transaction) {
  case transaction {
    TransactionBuy(_) -> Buy
    TransactionSale(_) -> Sale
  }
}

pub type BuyTransaction {
  BuyTransaction(
    asset: String,
    date: Date,
    id: String,
    buy_fee: Float,
    buy_price: Float,
    buy_price_each_after_fee: Float,
    buy_price_total: Float,
    buy_price_total_after_fee: Float,
    buy_qty: Float,
  )
}

pub type SaleTransaction {
  SaleTransaction(
    asset: String,
    date: Date,
    id: String,
    sale_fee: Float,
    sale_price: Float,
    sale_price_each_after_fee: Float,
    sale_price_total: Float,
    sale_price_total_after_fee: Float,
    sale_qty: Float,
  )
}

pub type SaleAllocation {
  SaleAllocation(
    buy_date: Date,
    buy_price_each: Float,
    buy_price_total: Float,
    buy_transaction_id: String,
    capital_gain: Float,
    asset: String,
    days_held: Int,
    id: Uuid,
    qty: Float,
    sale_date: Date,
    sale_price_each: Float,
    sale_price_total: Float,
    sale_transaction_id: String,
  )
}

type ReportColumn {
  ColFY
  ColAsset
  ColBuyDate
  ColSaleDate
  ColBuyId
  ColSaleId
  ColQty
  ColBuyPriceEach
  ColBuyPriceTotal
  ColSalePriceEach
  ColSalePriceTotal
  ColCapitalGain
  ColCapitalGainDiscounted
  ColCGTDiscount
}

const report_columns = [
  ColFY,
  ColSaleDate,
  ColAsset,
  ColBuyDate,
  ColBuyId,
  ColSaleId,
  ColQty,
  ColBuyPriceEach,
  ColBuyPriceTotal,
  ColSalePriceEach,
  ColSalePriceTotal,
  ColCapitalGain,
  ColCapitalGainDiscounted,
  ColCGTDiscount,
]

pub fn with_context(error_context, next) {
  next()
  |> outcome.context(error_context)
}

pub type Acc {
  Acc(allocations: List(SaleAllocation))
}

fn calculate_sale_allocations(
  transactions: List(Transaction),
) -> Outcome(List(SaleAllocation), String) {
  let buy_transactions =
    list.filter_map(transactions, fn(t) {
      case t {
        TransactionBuy(t) -> Ok(t)
        _ -> Error(Nil)
      }
    })

  let sale_transactions =
    list.filter_map(transactions, fn(t) {
      case t {
        TransactionSale(t) -> Ok(t)
        _ -> Error(Nil)
      }
    })

  let initial = Acc(allocations: [])

  list.try_fold(
    sale_transactions,
    initial,
    fn(acc: Acc, transaction: SaleTransaction) {
      let relevant_buy_transactions =
        buy_transactions
        |> list.filter(fn(t) { t.asset == transaction.asset })

      let allocations_for_this_asset =
        acc.allocations
        |> list.filter(fn(a) { a.asset == transaction.asset })

      use new_allocations <- result.try(allocate_sale_transaction(
        transaction,
        relevant_buy_transactions,
        allocations_for_this_asset,
      ))

      let next_allocations = list.append(acc.allocations, new_allocations)

      Ok(Acc(next_allocations))
    },
  )
  |> result.map(fn(acc) { acc.allocations })
}

type GenericReport {
  GenericReport(headers: List(String), rows: List(List(String)))
}

type TransactionCol {
  TransactionColId
  TransactionColAsset
  TransactionColDate
  TransactionColKind
  TransactionColBuyPriceEach
  TransactionColBuyPriceTotal
  TransactionColBuyQty
  TransactionColBuyFee
  TransactionColBuyPriceEachAfterFee
  TransactionColBuyTotalAfterFee
  TransactionColSalePriceEach
  TransactionColSalePriceTotal
  TransactionColSaleQty
  TransactionColSaleFee
  TransactionColSalePriceEachAfterFee
  TransactionColSaleTotalAfterFee
}

const transaction_columns = [
  TransactionColId,
  TransactionColDate,
  TransactionColAsset,
  TransactionColKind,
  TransactionColBuyQty,
  TransactionColBuyPriceEach,
  TransactionColBuyPriceTotal,
  TransactionColBuyFee,
  TransactionColBuyPriceEachAfterFee,
  TransactionColBuyTotalAfterFee,
  TransactionColSaleQty,
  TransactionColSalePriceEach,
  TransactionColSalePriceTotal,
  TransactionColSaleFee,
  TransactionColSalePriceEachAfterFee,
  TransactionColSaleTotalAfterFee,
]

pub fn transactions_table(transactions: List(Transaction)) {
  let headers = transaction_columns |> list.map(transaction_col_header_to_label)

  let rows =
    transactions
    |> list.map(transaction_to_table_row)

  gtabler.print_table(table_config(), headers, rows)
}

fn transaction_col_header_to_label(col: TransactionCol) {
  case col {
    TransactionColAsset -> "Asset"
    TransactionColBuyFee -> "B fee"
    TransactionColBuyPriceEach -> "B pr"
    TransactionColBuyPriceEachAfterFee -> "B pr+fee"
    TransactionColBuyPriceTotal -> "B tot"
    TransactionColBuyQty -> "B qty"
    TransactionColBuyTotalAfterFee -> "B tot+fee"
    TransactionColDate -> "Date"
    TransactionColId -> "Id"
    TransactionColKind -> "Kind"
    TransactionColSaleFee -> "S fee"
    TransactionColSalePriceEach -> "S pr"
    TransactionColSalePriceEachAfterFee -> "S pr-fee"
    TransactionColSalePriceTotal -> "S tot"
    TransactionColSaleQty -> "S qty"
    TransactionColSaleTotalAfterFee -> "S tot-fee"
  }
}

fn transaction_to_table_row(transaction: Transaction) {
  transaction_columns
  |> list.map(transaction_to_table_cell(_, transaction))
}

fn transaction_to_table_cell(col: TransactionCol, transaction: Transaction) {
  case col {
    TransactionColId -> transaction_id(transaction)
    TransactionColAsset -> transaction_asset(transaction)
    TransactionColDate -> transaction |> transaction_date |> date_to_label
    TransactionColKind -> transaction |> transaction_kind |> kind_to_label
    TransactionColBuyPriceEach -> {
      case transaction {
        TransactionBuy(t) -> t.buy_price |> format_amount
        _ -> ""
      }
    }
    TransactionColBuyPriceTotal -> {
      case transaction {
        TransactionBuy(t) -> t.buy_price_total |> format_amount
        _ -> ""
      }
    }
    TransactionColBuyQty -> {
      case transaction {
        TransactionBuy(t) -> t.buy_qty |> format_amount
        _ -> ""
      }
    }
    TransactionColBuyFee -> {
      case transaction {
        TransactionBuy(t) -> t.buy_fee |> format_amount
        _ -> ""
      }
    }
    TransactionColBuyPriceEachAfterFee -> {
      case transaction {
        TransactionBuy(t) -> t.buy_price_each_after_fee |> format_amount
        _ -> ""
      }
    }
    TransactionColBuyTotalAfterFee -> {
      case transaction {
        TransactionBuy(t) -> t.buy_price_total_after_fee |> format_amount
        _ -> ""
      }
    }
    TransactionColSalePriceEach -> {
      case transaction {
        TransactionSale(t) -> t.sale_price |> format_amount
        _ -> ""
      }
    }
    TransactionColSalePriceTotal -> {
      case transaction {
        TransactionSale(t) -> t.sale_price_total |> format_amount
        _ -> ""
      }
    }
    TransactionColSaleQty -> {
      case transaction {
        TransactionSale(t) -> t.sale_qty |> format_amount
        _ -> ""
      }
    }
    TransactionColSaleFee -> {
      case transaction {
        TransactionSale(t) -> t.sale_fee |> format_amount
        _ -> ""
      }
    }
    TransactionColSalePriceEachAfterFee -> {
      case transaction {
        TransactionSale(t) -> t.sale_price_each_after_fee |> format_amount
        _ -> ""
      }
    }
    TransactionColSaleTotalAfterFee -> {
      case transaction {
        TransactionSale(t) -> t.sale_price_total_after_fee |> format_amount
        _ -> ""
      }
    }
  }
}

fn generic_report(transactions: List(Transaction)) {
  use _ <- result.try(assert_no_duplicate_ids(transactions))

  use allocations <- result.try(calculate_sale_allocations(transactions))

  let headers = report_columns |> list.map(header_to_label)

  let rows =
    allocations
    |> list.map(sale_allocation_to_report_line)

  let report = GenericReport(headers:, rows:)

  Ok(report)
}

pub fn report_csv(transactions: List(Transaction)) {
  use report <- result.try(generic_report(transactions))

  list.append([report.headers], report.rows)
  |> gsv.from_lists(separator: ",", line_ending: gsv.Unix)
  |> Ok
}

pub fn report_table(transactions: List(Transaction)) {
  use report <- result.try(generic_report(transactions))

  gtabler.print_table(table_config(), report.headers, report.rows)
  |> Ok
}

fn table_config() {
  gtabler.TableConfig(
    separator: "|",
    border_char: "-",
    header_color: fn(text) { text },
    cell_color: fn(text) { text },
  )
}

fn header_to_label(column: ReportColumn) {
  case column {
    ColBuyDate -> "Buy date"
    ColBuyId -> "Buy Id"
    ColBuyPriceEach -> "Buy unit"
    ColBuyPriceTotal -> "Buy total"
    ColCapitalGain -> "Gain"
    ColCapitalGainDiscounted -> "Gain d."
    ColAsset -> "Coin"
    ColFY -> "FY"
    ColQty -> "Qty"
    ColCGTDiscount -> "CGT Discount"
    ColSaleDate -> "Sale date"
    ColSaleId -> "Sale Id"
    ColSalePriceEach -> "Sale unit"
    ColSalePriceTotal -> "Sale total"
  }
}

fn sale_allocation_to_report_line(allocation: SaleAllocation) {
  list.map(report_columns, sale_allocation_report_cell(_, allocation))
}

fn sale_allocation_report_cell(column: ReportColumn, allocation: SaleAllocation) {
  let gain = allocation.capital_gain
  let has_discount = allocation.days_held > 365

  let gain_after_discount = case has_discount {
    True -> gain /. 2.0
    False -> gain
  }

  case column {
    ColFY -> allocation.sale_date |> date_to_financial_year
    ColBuyDate -> allocation.buy_date |> date_to_label
    ColBuyId -> allocation.buy_transaction_id
    ColBuyPriceEach -> allocation.buy_price_each |> format_amount
    ColBuyPriceTotal ->
      allocation.buy_price_total
      |> format_amount
    ColCapitalGain ->
      gain
      |> format_amount
    ColCapitalGainDiscounted ->
      gain_after_discount
      |> format_amount
    ColAsset -> allocation.asset
    ColQty ->
      allocation.qty
      |> format_amount
    ColCGTDiscount -> {
      case has_discount {
        True -> "Yes"
        False -> ""
      }
    }
    ColSaleDate -> allocation.sale_date |> date_to_label
    ColSaleId -> allocation.sale_transaction_id
    ColSalePriceEach ->
      allocation.sale_price_each
      |> format_amount
    ColSalePriceTotal ->
      allocation.sale_price_total
      |> format_amount
  }
}

fn date_to_label(date: Date) {
  date.to_string(date)
}

import tempo/month

fn date_to_financial_year(date: Date) {
  let month = date.get_month(date) |> month.to_int
  let year = date.get_year(date)

  let fy = case month > 6 {
    True -> year + 1
    False -> year
  }

  "FY" <> int.to_string(fy)
}

fn allocate_sale_transaction(
  sale_transaction: SaleTransaction,
  relevant_buy_transactions: List(BuyTransaction),
  allocations_for_this_asset: List(SaleAllocation),
) -> Outcome(List(SaleAllocation), String) {
  use <- with_context("sale_transaction " <> sale_transaction.id)

  let allocations_for_this_sale_transaction =
    allocations_for_this_asset
    |> list.filter(fn(alloc) {
      alloc.sale_transaction_id == sale_transaction.id
    })

  let qty_allocated_so_far =
    allocations_for_this_sale_transaction
    |> list.map(fn(alloc) { alloc.qty })
    |> float.sum

  let remainding_qty_to_allocate =
    sale_transaction.sale_qty -. qty_allocated_so_far

  // echo "remainding_qty_to_allocate"
  // echo remainding_qty_to_allocate

  use <- given.that(remainding_qty_to_allocate >. 0.0, else_return: fn() {
    Ok(allocations_for_this_sale_transaction)
  })

  // Try the next buy transaction
  case relevant_buy_transactions {
    [buy_transaction, ..rest_buy_transactions] -> {
      // buy transaction must be before sale transaction

      let buy_is_earlier_or_equal =
        date.is_earlier_or_equal(buy_transaction.date, sale_transaction.date)

      use <- given.that(buy_is_earlier_or_equal, else_return: fn() {
        allocate_sale_transaction(
          sale_transaction,
          rest_buy_transactions,
          allocations_for_this_asset,
        )
      })

      let allocations_for_this_buy_transaction =
        allocations_for_this_asset
        |> list.filter(fn(alloc) {
          alloc.buy_transaction_id == buy_transaction.id
        })

      let qty_allocated_so_far_for_buy_transaction =
        allocations_for_this_buy_transaction
        |> list.map(fn(alloc) { alloc.qty })
        |> float.sum

      // echo "qty_allocated_so_far_for_buy_transaction"
      // echo qty_allocated_so_far_for_buy_transaction

      let remainder_to_allocate_for_buy =
        buy_transaction.buy_qty -. qty_allocated_so_far_for_buy_transaction

      // echo "remainder_to_allocate_for_buy"
      // echo remainder_to_allocate_for_buy

      use <- given.that(remainder_to_allocate_for_buy >. 0.0, else_return: fn() {
        allocate_sale_transaction(
          sale_transaction,
          rest_buy_transactions,
          allocations_for_this_asset,
        )
      })

      let allocation_qty =
        float.min(remainder_to_allocate_for_buy, remainding_qty_to_allocate)

      // echo "allocation_qty"
      // echo allocation_qty

      let buy_price_each = buy_transaction.buy_price_each_after_fee
      let buy_price_total = allocation_qty *. buy_price_each

      let sale_price_each = sale_transaction.sale_price_each_after_fee
      let sale_price_total = allocation_qty *. sale_price_each

      let capital_gain = sale_price_total -. buy_price_total

      let days_held =
        date.difference(from: buy_transaction.date, to: sale_transaction.date)

      let new_allocation =
        SaleAllocation(
          buy_date: buy_transaction.date,
          buy_price_each:,
          buy_price_total:,
          buy_transaction_id: buy_transaction.id,
          capital_gain:,
          asset: sale_transaction.asset,
          id: uuid.v4(),
          qty: allocation_qty,
          days_held:,
          sale_date: sale_transaction.date,
          sale_transaction_id: sale_transaction.id,
          sale_price_each:,
          sale_price_total:,
        )

      // echo "new_allocation"
      // echo new_allocation

      let next_allocations =
        list.append(allocations_for_this_asset, [new_allocation])

      allocate_sale_transaction(
        sale_transaction,
        rest_buy_transactions,
        next_allocations,
      )
    }
    _ -> {
      Error("No buy transactions left")
      |> outcome
      |> outcome.context(
        "qty_allocated_so_far " <> float.to_string(qty_allocated_so_far),
      )
      |> outcome.context(
        "remainding_qty_to_allocate "
        <> float.to_string(remainding_qty_to_allocate),
      )
    }
  }
}

// Qty or currency
pub fn format_amount(amount: Float) -> String {
  let left =
    float.truncate(amount)
    |> int.to_string

  let absolute_value = amount |> float.absolute_value
  let integer = float.floor(absolute_value)

  let decimals =
    absolute_value -. integer
    |> float.to_precision(3)
    |> float.to_string
    |> string.drop_start(2)

  left <> "." <> decimals
}

pub fn make_buy_transaction(
  asset asset: String,
  date date: Date,
  id id: String,
  buy_fee buy_fee: Float,
  buy_price buy_price: Float,
  buy_qty buy_qty: Float,
) {
  let buy_price_total = buy_qty *. buy_price

  let buy_price_total_after_fee = buy_price_total +. buy_fee

  let buy_price_each_after_fee = buy_price_total_after_fee /. buy_qty

  BuyTransaction(
    asset:,
    date:,
    id:,
    buy_fee:,
    buy_price:,
    buy_price_total:,
    buy_qty:,
    buy_price_total_after_fee:,
    buy_price_each_after_fee:,
  )
  |> TransactionBuy
}

pub fn make_sale_transaction(
  asset asset: String,
  date date: Date,
  id id: String,
  sale_fee sale_fee: Float,
  sale_price sale_price: Float,
  sale_qty sale_qty: Float,
) {
  let sale_price_total = sale_qty *. sale_price

  let sale_price_total_after_fee = sale_price_total -. sale_fee

  let sale_price_each_after_fee = sale_price_total_after_fee /. sale_qty

  SaleTransaction(
    asset:,
    date:,
    id:,
    sale_fee:,
    sale_price:,
    sale_price_total:,
    sale_qty:,
    sale_price_total_after_fee:,
    sale_price_each_after_fee:,
  )
  |> TransactionSale
}

import tempo/date
import tempo/error.{type DateParseError}

fn date_parse_error_to_label(error: DateParseError) {
  case error {
    error.DateInvalidFormat(input) -> "Invalid date format " <> input
    error.DateOutOfBounds(input, _) -> "Date out of bounds " <> input
  }
}

pub fn parse_date(input: String) -> outcome.Outcome(Date, String) {
  date.parse(input, tempo.CustomDate("DD/MM/YYYY"))
  |> result.or(date.parse(input, tempo.CustomDate("D/MM/YYYY")))
  |> result.or(date.parse(input, tempo.CustomDate("D/M/YYYY")))
  |> result.map_error(date_parse_error_to_label)
  |> outcome
  |> outcome.context("When parsing " <> input)
}

fn parse_input(content: String) {
  use csv <- result.try(
    gsv.to_dicts(content, ",")
    |> result.replace_error("Unable to parse CSV")
    |> outcome,
  )

  csv
  |> list.index_map(fn(line, ix) { #(ix + 2, line) })
  |> list.try_map(parse_input_line)
}

fn get_str(row, attr) {
  dict.get(row, attr)
  |> result.replace_error("Couldn't find " <> attr)
  |> outcome
}

fn get_date(row, attr) {
  use date_str <- result.try(
    dict.get(row, attr)
    |> result.replace_error("Couldn't find " <> attr)
    |> outcome,
  )

  parse_date(date_str)
}

fn get_float(row, attr) {
  use str <- result.try(
    dict.get(row, attr)
    |> result.replace_error("Couldn't find " <> attr)
    |> outcome,
  )
  str |> parse_float
}

fn parse_input_line(
  tuple: #(Int, dict.Dict(String, String)),
) -> Outcome(Transaction, String) {
  let #(line_index, row) = tuple

  use <- with_context("line " <> int.to_string(line_index))

  use id <- result.try(get_str(row, "id"))

  use asset <- result.try(get_str(row, "asset"))

  use kind_str <- result.try(get_str(row, "kind"))

  use date <- result.try(get_date(row, "date"))

  use kind <- result.try(
    kind_from_code(kind_str) |> outcome |> outcome.context("kind"),
  )

  case kind {
    Buy -> {
      use buy_qty <- result.try(get_float(row, "buy_qty"))

      use buy_price <- result.try(get_float(row, "buy_price"))

      use buy_fee <- result.try(get_float(row, "buy_fee"))

      make_buy_transaction(asset:, date:, id:, buy_fee:, buy_price:, buy_qty:)
      |> Ok
    }
    Sale -> {
      use sale_qty <- result.try(get_float(row, "sale_qty"))

      use sale_price <- result.try(get_float(row, "sale_price"))

      use sale_fee <- result.try(get_float(row, "sale_fee"))

      make_sale_transaction(
        asset:,
        date:,
        id:,
        sale_fee:,
        sale_price:,
        sale_qty:,
      )
      |> Ok
    }
  }
}

fn parse_int(input: String) {
  input
  |> string.trim
  |> string.replace(",", "")
  |> int.parse
  |> result.replace_error("Unable to parse int " <> input)
  |> outcome
}

fn parse_float(input: String) {
  let result =
    input
    |> string.trim
    |> string.replace(",", "")
    |> float.parse
    |> result.replace_error("Unable to parse float " <> input)
    |> outcome

  case result {
    Ok(float) -> Ok(float)
    Error(float_err) -> {
      case parse_int(input) {
        Ok(int) -> Ok(int.to_float(int))
        Error(_) -> Error(float_err)
      }
    }
  }
}

fn read_input(file_path: String) -> Outcome(List(Transaction), String) {
  use content <- result.try(
    simplifile.read(from: file_path)
    |> result.replace_error("Unable to read " <> file_path)
    |> outcome,
  )

  parse_input(content)
}

fn assert_no_duplicate_ids(transactions: List(Transaction)) {
  let ids =
    transactions
    |> list.map(fn(t) {
      case t {
        TransactionBuy(buy) -> buy.id
        TransactionSale(sale) -> sale.id
      }
    })

  let id_count = list.length(ids)
  let id_count_check = set.from_list(ids) |> set.size

  case id_count_check == id_count {
    True -> Ok(transactions)
    False -> Error("Duplicate ids found ") |> outcome
  }
}

fn write_output(report: String, file_path: String) -> Outcome(Nil, String) {
  simplifile.write(to: file_path, contents: report)
  |> result.replace_error("Unable to write to " <> file_path)
  |> outcome
}

fn process_file(in_path: String, out_path: String) {
  use transactions <- result.try(read_input(in_path))
  use report <- result.try(report_csv(transactions))
  use _ <- result.try(write_output(report, out_path))
  Ok("Done")
}

type CliArgs {
  CliArgs(file: String)
}

fn file_opt() -> Opt(String) {
  opt.new("file") |> opt.help("File to process")
}

fn command() -> Command(CliArgs) {
  clip.command({
    use file <- clip.parameter

    CliArgs(file)
  })
  |> clip.opt(file_opt())
}

pub fn main() -> Nil {
  let result =
    command()
    |> clip.help(help.simple("file", "Process a file"))
    |> clip.run(argv.load().arguments)

  use args <- given.ok(result, else_return: fn(e) { io.println_error(e) })

  let in_path = "./.data/" <> args.file <> ".csv"
  let out_path = "./.data/" <> args.file <> "_out.csv"

  case process_file(in_path, out_path) {
    Ok(message) -> io.println(message)
    Error(e) -> io.println_error(outcome.print_line(e, function.identity))
  }
}
