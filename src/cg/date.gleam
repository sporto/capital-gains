import gleam/int
import gleam/order
import gleam/result
import outcome
import tempo
import tempo/date
import tempo/error
import tempo/month

pub type Date =
  tempo.Date

pub fn parse(input: String) -> outcome.Outcome(Date, String) {
  date.parse(input, tempo.CustomDate("DD/MM/YYYY"))
  |> result.or(date.parse(input, tempo.CustomDate("D/MM/YYYY")))
  |> result.or(date.parse(input, tempo.CustomDate("D/M/YYYY")))
  |> result.or(date.parse(input, tempo.CustomDate("YYYY-MM-DD")))
  |> result.map_error(describe_date_parse_error)
  |> outcome.outcome
  |> outcome.context("When parsing " <> input)
}

fn describe_date_parse_error(error: error.DateParseError) {
  case error {
    error.DateInvalidFormat(input) -> "Invalid date format " <> input
    error.DateOutOfBounds(input, _) -> "Date out of bounds " <> input
  }
}

pub fn compare(a: Date, b: Date) -> order.Order {
  date.compare(a, b)
}

pub fn to_string(date: Date) -> String {
  date.to_string(date)
}

pub fn to_financial_year(date: Date) {
  let year = date.get_year(date)

  let month =
    date.get_month(date)
    |> month.to_int

  let fy = case month > 6 {
    True -> year + 1
    False -> year
  }

  "FY" <> int.to_string(fy)
}
