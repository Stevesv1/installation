use crate::config;
use crate::flops::measure_flops;
use crate::memory_stats::get_memory_info;
use crate::nexus_orchestrator::{
    GetProofTaskRequest, GetProofTaskResponse, NodeType, SubmitProofRequest,
};
use prost::Message;
use reqwest::Client;

pub struct OrchestratorClient {
    client: Client,
    base_url: String,
}

impl OrchestratorClient {
    pub fn new(environment: config::Environment) -> Self {
        Self {
            client: Client::new(),
            base_url: environment.orchestrator_url(),
        }
    }

    // Added better error handling for Protobuf encoding
    async fn make_request<T, U>(
        &self,
        url: &str,
        method: &str,
        request_data: &T,
    ) -> Result<Option<U>, Box<dyn std::error::Error>>
    where
        T: Message,
        U: Message + Default,
    {
        let request_bytes = request_data.encode_to_vec();
        let url = format!("{}{}", self.base_url, url);

        let response = match method {
            "POST" => self.client.post(&url),
            "GET" => self.client.get(&url),
            _ => return Err("Unsupported HTTP method".into()),
        };

        let response = response
            .header("Content-Type", "application/octet-stream")
            .body(request_bytes)
            .send()
            .await
            .map_err(|_| "Failed to connect to orchestrator")?;

        if !response.status().is_success() {
            let status = response.status();
            let error_text = response.text().await?;
            return Err(format!("HTTP {}: {}", status, error_text).into());
        }

        let response_bytes = response.bytes().await?;
        if response_bytes.is_empty() {
            return Ok(None);
        }

        U::decode(response_bytes)
            .map(Some)
            .map_err(|e| format!("Protobuf decode error: {}", e).into())
    }

    // Added input validation
    pub async fn get_proof_task(
        &self,
        node_id: &str,
    ) -> Result<GetProofTaskResponse, Box<dyn std::error::Error>> {
        if node_id.is_empty() {
            return Err("Invalid node ID".into());
        }

        let request = GetProofTaskRequest {
            node_id: node_id.to_string(),
            node_type: NodeType::CliProver as i32,
        };

        self.make_request("/tasks", "POST", &request)
            .await?
            .ok_or_else(|| "Empty response from orchestrator".into())
    }

    // Added proof validation before submission
    pub async fn submit_proof(
        &self,
        node_id: &str,
        proof_hash: &str,
        proof: Vec<u8>,
    ) -> Result<(), Box<dyn std::error::Error>> {
        if proof.is_empty() {
            return Err("Empty proof submitted".into());
        }

        let (program_memory, total_memory) = get_memory_info();
        let flops = measure_flops();

        let request = SubmitProofRequest {
            node_id: node_id.to_string(),
            node_type: NodeType::CliProver as i32,
            proof_hash: proof_hash.to_string(),
            proof,
            node_telemetry: Some(crate::nexus_orchestrator::NodeTelemetry {
                flops_per_sec: Some(flops as i32),
                memory_used: Some(program_memory),
                memory_capacity: Some(total_memory),
                location: Some("US".to_string()),
            }),
        };

        self.make_request::<SubmitProofRequest, ()>("/tasks/submit", "POST", &request)
            .await?;

        println!("\tNexus Orchestrator: Proof submitted successfully");
        Ok(())
    }
}
