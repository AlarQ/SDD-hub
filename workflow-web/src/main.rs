//! Thin binary shell — all logic lives in the library so integration tests
//! exercise the same code paths. Exit codes per ADR-010 (0/2/4/7).

#[tokio::main]
async fn main() {
    let code = workflow_web::run().await;
    std::process::exit(code);
}
