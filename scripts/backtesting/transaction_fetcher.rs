#!/usr/bin/env rust-script
//! ```cargo
//! [dependencies]
//! serde = { version = "1.0", features = ["derive"] }
//! serde_json = "1.0"
//! reqwest = { version = "0.11", features = ["json"] }
//! tokio = { version = "1.0", features = ["full"] }
//! clap = { version = "4.0", features = ["derive"] }
//! hex = "0.4"
//! ethabi = "18.0"
//! futures = "0.3"
//! ```

use serde::{Deserialize, Serialize};

use std::time::Instant;
use clap::{Arg, Command};
use futures::stream::{self, StreamExt};
use std::sync::Arc;

#[derive(Debug, Serialize, Deserialize)]
struct Transaction {
    hash: String,
    from: String,
    to: Option<String>,
    value: String,
    input: String,
    #[serde(rename = "transactionIndex")]
    transaction_index: String,
    #[serde(rename = "gasPrice")]
    gas_price: String,
}

#[derive(Debug, Serialize, Deserialize)]
struct Block {
    transactions: Vec<Transaction>,
    number: String,
    #[serde(rename = "baseFeePerGas")]
    base_fee_per_gas: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
struct RpcResponse {
    result: Block,
}

#[derive(Debug, Serialize)]
struct FilteredTransaction {
    hash: String,
    from: String,
    to: String,
    value: String,
    data: String,
    block_number: String,
    transaction_index: String,
    gas_price: String,
}

/// Fetch transactions from a block that interact with a target contract
async fn fetch_block_transactions(
    client: &reqwest::Client,
    rpc_url: &str,
    block_number: u64,
    target_contract: &str,
) -> Result<Vec<FilteredTransaction>, Box<dyn std::error::Error>> {
    // Convert block number to hex
    let block_hex = format!("0x{:x}", block_number);
    
    // Prepare RPC request
    let rpc_request = serde_json::json!({
        "jsonrpc": "2.0",
        "method": "eth_getBlockByNumber",
        "params": [block_hex, true],
        "id": 1
    });

    // Make the request using the shared client
    let response = client
        .post(rpc_url)
        .header("Content-Type", "application/json")
        .json(&rpc_request)
        .send()
        .await?;

    let rpc_response: RpcResponse = response.json().await?;
    let block = rpc_response.result;

    // Filter transactions that interact with the target contract
    let target_contract_lower = target_contract.to_lowercase();
    let mut filtered_transactions = Vec::new();

    for tx in block.transactions {
        // Check if transaction is sent to the target contract
        if let Some(to) = &tx.to {
            if to.to_lowercase() == target_contract_lower {
                // Convert hex block number to decimal string
                let block_num_decimal = if block.number.starts_with("0x") {
                    u64::from_str_radix(&block.number[2..], 16)
                        .unwrap_or_else(|_| panic!("Invalid hex block number: {}", block.number))
                        .to_string()
                } else {
                    block.number.clone()
                };

                // Convert hex transaction index to decimal string
                let tx_index_decimal = if tx.transaction_index.starts_with("0x") {
                    u64::from_str_radix(&tx.transaction_index[2..], 16)
                        .unwrap_or_else(|_| panic!("Invalid hex transaction index: {}", tx.transaction_index))
                        .to_string()
                } else {
                    tx.transaction_index.clone()
                };

                filtered_transactions.push(FilteredTransaction {
                    hash: tx.hash,
                    from: tx.from,
                    to: to.clone(),
                    value: tx.value,
                    data: tx.input,
                    block_number: block_num_decimal,
                    transaction_index: tx_index_decimal,
                    gas_price: tx.gas_price,
                });
            }
        }
    }

    Ok(filtered_transactions)
}

/// Fetch transactions from multiple blocks in parallel with batching
async fn fetch_block_range_transactions_optimized(
    rpc_url: &str,
    start_block: u64,
    end_block: u64,
    target_contract: &str,
    batch_size: usize,
    max_concurrent: usize,
) -> Result<Vec<FilteredTransaction>, Box<dyn std::error::Error>> {
    let start_time = Instant::now();
    println!("Starting optimized fetch: blocks {} to {} (batch size: {}, max concurrent: {})", 
             start_block, end_block, batch_size, max_concurrent);

    // Create a shared HTTP client with connection pooling
    let client = reqwest::Client::builder()
        .pool_max_idle_per_host(10)
        .timeout(std::time::Duration::from_secs(30))
        .build()?;

    let client = Arc::new(client);
    let target_contract = Arc::new(target_contract.to_string());
    let rpc_url = Arc::new(rpc_url.to_string());

    let mut all_transactions = Vec::new();
    let mut total_blocks_processed = 0;
    let mut total_transactions_found = 0;

    // Process blocks in batches
    for batch_start in (start_block..=end_block).step_by(batch_size) {
        let batch_end = std::cmp::min(batch_start + batch_size as u64 - 1, end_block);
        let batch_blocks: Vec<u64> = (batch_start..=batch_end).collect();
        
        println!("Processing batch: blocks {} to {}", batch_start, batch_end);

        // Process blocks in this batch concurrently
        let futures = batch_blocks.into_iter().map(|block_num| {
            let client = Arc::clone(&client);
            let target_contract = Arc::clone(&target_contract);
            let rpc_url = Arc::clone(&rpc_url);
            
            async move {
                match fetch_block_transactions(&client, &rpc_url, block_num, &target_contract).await {
                    Ok(transactions) => {
                        if !transactions.is_empty() {
                            println!("  Block {}: found {} transactions", block_num, transactions.len());
                        }
                        Ok((block_num, transactions))
                    }
                    Err(e) => {
                        eprintln!("  Error fetching block {}: {}", block_num, e);
                        Err(e)
                    }
                }
            }
        });

        // Execute with concurrency limit
        let batch_results: Vec<_> = stream::iter(futures)
            .buffer_unordered(max_concurrent)
            .collect()
            .await;

        // Collect results from this batch
        for result in batch_results {
            match result {
                Ok((_block_num, transactions)) => {
                    total_blocks_processed += 1;
                    total_transactions_found += transactions.len();
                    all_transactions.extend(transactions);
                }
                Err(_) => {
                    // Error already logged above
                }
            }
        }
    }

    let duration = start_time.elapsed();
    println!("Optimized fetch completed in {:?}", duration);
    println!("Processed {} blocks, found {} transactions", total_blocks_processed, total_transactions_found);
    println!("Average: {:.2} blocks/sec, {:.2} transactions/sec", 
             total_blocks_processed as f64 / duration.as_secs_f64(),
             total_transactions_found as f64 / duration.as_secs_f64());

    Ok(all_transactions)
}

/// Encode transaction data for Foundry consumption
fn encode_transactions_for_foundry(transactions: &[FilteredTransaction], output_format: &str) -> String {
    match output_format {
        "simple" => encode_simple_format(transactions),
        "json" => serde_json::to_string(transactions).unwrap_or_else(|_| "[]".to_string()),
        _ => encode_simple_format(transactions),
    }
}

/// Encode transactions in a simple pipe-delimited format that's easy to parse in Solidity
fn encode_simple_format(transactions: &[FilteredTransaction]) -> String {
    if transactions.is_empty() {
        return "0".to_string();
    }
    
    let mut result = format!("{}", transactions.len());
    
    for tx in transactions {
        // Format: hash|from|to|value|data|blockNumber|txIndex|gasPrice
        result.push('|');
        result.push_str(&tx.hash);
        result.push('|');
        result.push_str(&tx.from);
        result.push('|');
        result.push_str(&tx.to);
        result.push('|');
        result.push_str(&tx.value);
        result.push('|');
        result.push_str(&tx.data);
        result.push('|');
        result.push_str(&tx.block_number);
        result.push('|');
        result.push_str(&tx.transaction_index);
        result.push('|');
        result.push_str(&tx.gas_price);
    }
    
    result
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let matches = Command::new("Transaction Fetcher")
        .about("Fetches blockchain transactions for backtesting")
        .arg(
            Arg::new("rpc-url")
                .long("rpc-url")
                .value_name("URL")
                .help("RPC endpoint URL")
                .required(true),
        )
        .arg(
            Arg::new("target-contract")
                .long("target-contract")
                .value_name("ADDRESS")
                .help("Contract address to filter transactions for")
                .required(true),
        )
        .arg(
            Arg::new("start-block")
                .long("start-block")
                .value_name("NUMBER")
                .help("Starting block number")
                .required(true),
        )
        .arg(
            Arg::new("end-block")
                .long("end-block")
                .value_name("NUMBER")
                .help("Ending block number")
                .required(true),
        )
        .arg(
            Arg::new("output-format")
                .long("output-format")
                .value_name("FORMAT")
                .help("Output format (simple, json)")
                .default_value("simple"),
        )
        .arg(
            Arg::new("batch-size")
                .long("batch-size")
                .value_name("SIZE")
                .help("Batch size for parallel processing (default: 10)")
                .default_value("10"),
        )
        .arg(
            Arg::new("max-concurrent")
                .long("max-concurrent")
                .value_name("COUNT")
                .help("Maximum concurrent requests (default: 5)")
                .default_value("5"),
        )
        .get_matches();

    let rpc_url = matches.get_one::<String>("rpc-url").unwrap();
    let target_contract = matches.get_one::<String>("target-contract").unwrap();
    let start_block: u64 = matches.get_one::<String>("start-block").unwrap().parse()?;
    let end_block: u64 = matches.get_one::<String>("end-block").unwrap().parse()?;
    let output_format = matches.get_one::<String>("output-format").unwrap();
    let batch_size: usize = matches.get_one::<String>("batch-size").unwrap().parse()?;
    let max_concurrent: usize = matches.get_one::<String>("max-concurrent").unwrap().parse()?;

    println!("TRANSACTION_DATA:START");
    
    let transactions = fetch_block_range_transactions_optimized(
        rpc_url,
        start_block,
        end_block,
        target_contract,
        batch_size,
        max_concurrent,
    ).await?;

    let encoded_data = encode_transactions_for_foundry(&transactions, output_format);
    print!("TRANSACTION_DATA:{}", encoded_data);
    print!("TRANSACTION_DATA:END");

    Ok(())
}