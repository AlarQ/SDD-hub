//! API error model. The response body carries only `{code, message}`; full
//! detail is logged server-side (SEC-FR-19 — no internal detail leaks to the
//! client). Handlers are added in task 004; the type is defined here so the
//! router skeleton compiles against a stable contract.

use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use axum::Json;
use serde::Serialize;

#[derive(Debug, Clone, Copy, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ErrorCode {
    NotFound,
    InvalidPath,
    TooLarge,
    BlockedHost,
    RateLimit,
    SseFull,
    Internal,
}

impl ErrorCode {
    fn status(self) -> StatusCode {
        match self {
            ErrorCode::NotFound => StatusCode::NOT_FOUND,
            ErrorCode::InvalidPath => StatusCode::BAD_REQUEST,
            ErrorCode::TooLarge => StatusCode::PAYLOAD_TOO_LARGE,
            ErrorCode::BlockedHost => StatusCode::FORBIDDEN,
            ErrorCode::RateLimit => StatusCode::TOO_MANY_REQUESTS,
            ErrorCode::SseFull => StatusCode::SERVICE_UNAVAILABLE,
            ErrorCode::Internal => StatusCode::INTERNAL_SERVER_ERROR,
        }
    }
}

#[derive(Debug, Clone, Serialize)]
pub struct ApiError {
    pub code: ErrorCode,
    pub message: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct ApiErrorResponse {
    pub error: ApiError,
}

impl ApiErrorResponse {
    pub fn new(code: ErrorCode, message: impl Into<String>) -> Self {
        ApiErrorResponse {
            error: ApiError {
                code,
                message: message.into(),
            },
        }
    }
}

impl IntoResponse for ApiErrorResponse {
    fn into_response(self) -> Response {
        (self.error.code.status(), Json(self)).into_response()
    }
}
