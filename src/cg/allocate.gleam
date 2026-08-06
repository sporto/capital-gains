import cg/allocation.{type Allocation, Allocation}
import cg/transaction.{type Transaction, Buy, Transaction}
import given
import gleam/float
import gleam/list
import gleam/result
import gleam/set
import outcome.{type Outcome}
import tempo/date
import youid/uuid

type TransactionsByAsset {
  TransactionsByAsset(
    asset: String,
    buys: List(Transaction),
    sales: List(Transaction),
  )
}

pub fn process(
  transactions: List(Transaction),
) -> Outcome(List(Allocation), String) {
  let assets =
    transactions
    |> list.map(fn(t) { t.asset })
    |> set.from_list

  let transactions_by_assets =
    assets
    |> set.to_list
    |> list.map(fn(asset) {
      let ts = list.filter(transactions, fn(t) { t.asset == asset })
      let #(buys, sales) = list.partition(ts, fn(t) { t.kind == Buy })
      TransactionsByAsset(asset:, buys:, sales:)
    })

  transactions_by_assets
  |> list.try_map(process_asset)
  |> result.map(list.flatten)
}

fn process_asset(
  data: TransactionsByAsset,
) -> Outcome(List(Allocation), String) {
  use <- outcome.with_context("@process_asset " <> data.asset)

  process_next_sale(
    asset: data.asset,
    remaining_buys: data.buys,
    remaining_sales: data.sales,
    allocations: [],
  )
}

fn require_next_transaction(transactions: List(Transaction), next) {
  case transactions {
    [] -> Error("Not enough transactions") |> outcome.outcome
    [first, ..rest] -> next(first, rest)
  }
}

fn process_next_sale(
  asset asset: String,
  remaining_buys remaining_buys: List(Transaction),
  remaining_sales remaining_sales: List(Transaction),
  allocations allocations: List(Allocation),
) -> Outcome(List(Allocation), String) {
  case remaining_sales {
    [] -> Ok(allocations)
    [current_sale, ..rest] ->
      process_sale_next_buy(
        asset:,
        remaining_buys:,
        remaining_sales: rest,
        current_sale:,
        allocations:,
      )
  }
}

fn process_sale_next_buy(
  allocations allocations: List(Allocation),
  asset asset: String,
  current_sale current_sale: Transaction,
  remaining_buys remaining_buys: List(Transaction),
  remaining_sales remaining_sales: List(Transaction),
) -> Outcome(List(Allocation), String) {
  use <- outcome.with_context(
    "@process_sale_next_buy current_sale " <> current_sale.id,
  )

  use <- given.that(
    current_sale.allocated <. current_sale.qty,
    else_return: fn() {
      // This sale fully allocated
      process_next_sale(asset:, remaining_buys:, remaining_sales:, allocations:)
    },
  )

  use current_buy, rest_buys <- require_next_transaction(remaining_buys)

  process_buy(
    allocations:,
    asset:,
    current_buy:,
    current_sale:,
    remaining_buys: rest_buys,
    remaining_sales:,
  )
}

fn process_buy(
  allocations allocations: List(Allocation),
  asset asset: String,
  current_buy current_buy: Transaction,
  current_sale current_sale: Transaction,
  remaining_buys remaining_buys: List(Transaction),
  remaining_sales remaining_sales: List(Transaction),
) -> Outcome(List(Allocation), String) {
  use <- outcome.with_context("@process_buy current_buy " <> current_buy.id)

  use <- given.not(asset == current_sale.asset, return: fn() {
    Error("Sale has wrong asset") |> outcome.outcome
  })

  let output = process_sale_and_buy(buy: current_buy, sale: current_sale)

  case output {
    EMismatchAssets | BuyConsumed -> {
      // Try the next buy
      process_sale_next_buy(
        allocations:,
        asset:,
        current_sale:,
        remaining_buys:,
        remaining_sales:,
      )
    }
    SaleFullyAllocated -> {
      process_next_sale(
        //
        allocations:,
        asset:,
        remaining_buys: [current_buy, ..remaining_buys],
        remaining_sales:,
      )
    }
    EInvalidKind -> {
      Error("Transactions have the wrong kind") |> outcome.outcome
    }
    EBadBuyDate -> {
      Error("Could not parse buy date") |> outcome.outcome
    }
    EBadSaleDate -> {
      Error("Could not parse sale date") |> outcome.outcome
    }
    ESaleIsEarlier -> {
      // The list must be sorted prior to this
      Error("Buy must be before sale") |> outcome.outcome
    }
    Allocated(updated_buy, updated_sale, allocation) -> {
      let next_allocations = list.append(allocations, [allocation])

      process_buy(
        allocations: next_allocations,
        asset:,
        current_sale: updated_sale,
        current_buy: updated_buy,
        remaining_buys:,
        remaining_sales:,
      )
    }
  }
}

pub type AllocationOutcome {
  EInvalidKind
  EMismatchAssets
  ESaleIsEarlier
  EBadBuyDate
  EBadSaleDate
  BuyConsumed
  SaleFullyAllocated
  Allocated(
    updated_buy: Transaction,
    updated_sale: Transaction,
    allocation: Allocation,
  )
}

pub fn process_sale_and_buy(
  buy buy: Transaction,
  sale sale: Transaction,
) -> AllocationOutcome {
  use <- given.that(buy.kind == Buy, else_return: fn() { EInvalidKind })

  use <- given.that(sale.kind == transaction.Sale, else_return: fn() {
    EInvalidKind
  })

  use <- given.that(buy.asset == sale.asset, else_return: fn() {
    EMismatchAssets
  })

  use <- given.that(sale.qty >. sale.allocated, else_return: fn() {
    SaleFullyAllocated
  })

  use <- given.that(
    date.is_earlier_or_equal(buy.date, sale.date),
    else_return: fn() { ESaleIsEarlier },
  )

  let available = buy.qty -. buy.allocated

  use <- given.not(available >. 0.0, return: fn() { BuyConsumed })

  let remainder_to_allocate = sale.qty -. sale.allocated

  let allocation_qty = float.min(remainder_to_allocate, available)

  let days_held = date.difference(from: buy.date, to: sale.date)

  let buy_fee_each = buy.fee /. buy.qty

  let buy_price_each_after_fee = buy.price_each +. buy_fee_each

  let buy_price_total = allocation_qty *. buy_price_each_after_fee

  let sale_fee_each = sale.fee /. sale.qty

  let sale_price_each_after_fee = sale.price_each -. sale_fee_each

  let sale_price_total = allocation_qty *. sale_price_each_after_fee

  let capital_gain = sale_price_total -. buy_price_total

  let allocation =
    Allocation(
      asset: sale.asset,
      buy_date: buy.date,
      buy_price_each: buy.price_each,
      buy_transaction_id: buy.id,
      capital_gain:,
      days_held:,
      id: uuid.v4(),
      qty: allocation_qty,
      sale_date: sale.date,
      sale_price_each: sale.price_each,
      sale_transaction_id: sale.id,
    )

  let updated_buy =
    Transaction(..buy, allocated: buy.allocated +. allocation_qty)

  let updated_sale =
    Transaction(..sale, allocated: sale.allocated +. allocation_qty)

  Allocated(updated_buy:, updated_sale:, allocation:)
}
