"""Future extension contracts; no external agents or retrieval run implicitly."""
from typing import Protocol
from pydantic import BaseModel

class Evidence(BaseModel):
    document_id: str
    page: int
    quote: str

class AgentResult(BaseModel):
    summary: str
    evidence: list[Evidence] = []

class ResearchAgent(Protocol):
    async def execute(self, task: str, document_ids: list[str]) -> AgentResult: ...

class Retriever(Protocol):
    async def search(self, query: str, owner_id: str) -> list[Evidence]: ...

class AccessPolicy(Protocol):
    def authorize(self, owner_id: str, resource_id: str) -> bool: ...
