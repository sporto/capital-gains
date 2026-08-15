import argv
import cg/allocate
import cg/allocation.{type Allocation}
import cg/date
import cg/transaction.{type Transaction, Buy, Sale, Transaction}
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
import outcome.{type Outcome}
import simplifile

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

  let in_path = args.file <> ".csv"
  let out_path = args.file <> "_out.csv"

  case process_file(in_path, out_path) {
    Ok(message) -> io.println(message)
    Error(e) -> io.println_error(outcome.pretty_print(e, function.identity))
  }
}

fn process_file(in_path: String, out_path: String) {
  use transactions <- result.try(read_input(in_path))
  use report <- result.try(report_csv(transactions))
  use _ <- result.try(write_output(report, out_path))
  Ok("Done")
}

fn read_input(file_path: String) -> Outcome(List(Transaction), String) {
  use content <- result.try(
    simplifile.read(from: file_path)
    |> result.replace_error("Unable to read " <> file_path)
    |> outcome.outcome,
  )

  parse_input(content)
}

fn parse_input(content: String) {
  let content = remove_empty_initial_grapheme(content)

  use csv <- result.try(
    gsv.to_dicts(content, ",")
    |> result.replace_error("Unable to parse CSV")
    |> outcome.outcome,
  )

  csv
  |> list.index_map(fn(line, ix) { #(ix + 2, line) })
  |> list.try_map(parse_input_line)
}

fn remove_empty_initial_grapheme(content: String) {
  case string.pop_grapheme(content) {
    Ok(#(first, _)) -> {
      case first {
        // Somehow we could have an invisible space
        "﻿" -> string.drop_start(content, 1)
        _ -> content
      }
    }
    Error(_) -> content
  }
}

fn parse_input_line(
  tuple: #(Int, dict.Dict(String, String)),
) -> Outcome(Transaction, String) {
  let #(line_index, row) = tuple

  use <- outcome.with_context("line " <> int.to_string(line_index))

  use id <- result.try(get_str(row, "id"))

  use asset <- result.try(get_str(row, "asset"))

  use kind_str <- result.try(get_str(row, "kind"))

  use date <- result.try(get_date(row, "date"))

  use kind <- result.try(
    kind_from_code(kind_str) |> outcome.outcome |> outcome.context("kind"),
  )

  use price_each <- result.try(get_float(row, "price_each"))

  use fee <- result.try(get_float(row, "fee"))

  use qty <- result.try(get_float(row, "qty"))

  let transaction =
    Transaction(
      allocated: 0.0,
      asset:,
      date:,
      fee:,
      id:,
      kind:,
      price_each:,
      qty:,
    )

  Ok(transaction)
}

fn get_float(row, attr) {
  use str <- result.try(
    dict.get(row, attr)
    |> result.replace_error("Couldn't find " <> attr)
    |> outcome.outcome,
  )
  str |> parse_float
}

fn get_str(row, attr) {
  dict.get(row, attr)
  |> result.replace_error("Couldn't find " <> attr)
  |> outcome.outcome
}

fn get_date(row, attr) -> Outcome(date.Date, String) {
  use date_str <- result.try(
    dict.get(row, attr)
    |> result.replace_error("Couldn't find " <> attr)
    |> outcome.outcome,
  )

  date.parse(date_str)
}

fn parse_float(input: String) {
  let result =
    input
    |> string.trim
    |> string.replace(",", "")
    |> float.parse
    |> result.replace_error("Unable to parse float " <> input)
    |> outcome.outcome

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

fn parse_int(input: String) {
  input
  |> string.trim
  |> string.replace(",", "")
  |> int.parse
  |> result.replace_error("Unable to parse int " <> input)
  |> outcome.outcome
}

fn kind_from_code(code: String) {
  case string.uppercase(code) {
    "BUY" -> Ok(Buy)
    "SALE" -> Ok(Sale)
    _ -> Error("Invalid transaction code " <> code)
  }
}

pub fn report_csv(transactions: List(Transaction)) {
  use report <- result.try(generic_report(transactions))

  list.append([report.headers], report.rows)
  |> gsv.from_lists(separator: ",", line_ending: gsv.Unix)
  |> Ok
}

pub type GenericReport {
  GenericReport(headers: List(String), rows: List(List(String)))
}

pub type ReportColumn {
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

pub const report_columns = [
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

pub fn generic_report(
  transactions: List(Transaction),
) -> Outcome(GenericReport, String) {
  use _ <- result.try(assert_no_duplicate_ids(transactions))

  use allocations <- result.try(allocate.process(transactions))

  let headers = report_columns |> list.map(header_to_label)

  let rows =
    allocations
    |> list.map(sale_allocation_to_report_line)

  let report = GenericReport(headers:, rows:)

  Ok(report)
}

pub fn header_to_label(column: ReportColumn) {
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

fn assert_no_duplicate_ids(transactions: List(Transaction)) {
  let ids =
    transactions
    |> list.map(fn(t) { t.id })

  let id_count = list.length(ids)
  let id_count_check = set.from_list(ids) |> set.size

  case id_count_check == id_count {
    True -> Ok(transactions)
    False -> {
      Error("Duplicate ids found") |> outcome.outcome
    }
  }
}

fn sale_allocation_to_report_line(allocation: Allocation) {
  list.map(report_columns, sale_allocation_report_cell(_, allocation))
}

fn sale_allocation_report_cell(column: ReportColumn, allocation: Allocation) {
  let gain = allocation.capital_gain
  let has_discount = allocation.days_held > 365

  let gain_after_discount = case has_discount {
    True -> gain /. 2.0
    False -> gain
  }

  let buy_price_total = allocation.buy_price_each *. allocation.qty

  let sale_price_total = allocation.sale_price_each *. allocation.qty

  case column {
    ColFY -> allocation.sale_date |> date.to_financial_year
    ColBuyDate -> allocation.buy_date |> date.to_string
    ColBuyId -> allocation.buy_transaction_id
    ColBuyPriceEach -> allocation.buy_price_each |> format_amount
    ColBuyPriceTotal ->
      buy_price_total
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
    ColSaleDate -> allocation.sale_date |> date.to_string
    ColSaleId -> allocation.sale_transaction_id
    ColSalePriceEach ->
      allocation.sale_price_each
      |> format_amount
    ColSalePriceTotal ->
      sale_price_total
      |> format_amount
  }
}

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

fn write_output(report: String, file_path: String) -> Outcome(Nil, String) {
  simplifile.write(to: file_path, contents: report)
  |> result.replace_error("Unable to write to " <> file_path)
  |> outcome.outcome
}
