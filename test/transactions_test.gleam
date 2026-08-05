import fixtures
import gleeunit
import outcome
import tempo/date
import transactions

pub fn main() -> Nil {
  gleeunit.main()
}

fn feb_1() {
  date.literal("2020-02-01")
}

fn feb_2() {
  date.literal("2020-02-02")
}

pub fn order_matters_test() {
  let actual =
    [
      // buy is after sale
      fixtures.fixture_sale()
        |> fixtures.w_id("a")
        |> fixtures.w_date(feb_1()),
      fixtures.fixture_buy()
        |> fixtures.w_id("b")
        |> fixtures.w_date(feb_2()),
    ]
    |> transactions.generic_report
    |> outcome.remove_problem

  assert actual == Error("Buy must be before")
}

pub fn duplicate_ids_test() {
  let actual =
    [
      fixtures.fixture_buy()
        |> fixtures.w_id("a")
        |> fixtures.w_date(feb_1()),
      fixtures.fixture_sale()
        |> fixtures.w_id("a")
        |> fixtures.w_date(feb_2()),
    ]
    |> transactions.generic_report
    |> outcome.remove_problem

  assert actual == Error("Duplicate ids")
}
