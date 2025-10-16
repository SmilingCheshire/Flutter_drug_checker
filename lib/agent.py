# agent.py
# Python 3.10+
# pip install fastapi uvicorn httpx pydantic
# (Later add: langchain, google-generativeai, etc.)

from typing import List, Optional
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import httpx

app = FastAPI(title="Drug Checker Agent")

OPEN_FDA_URL = "https://api.fda.gov/drug/label.json"

class DrugRequest(BaseModel):
  name: str

class DrugResponse(BaseModel):
  found: bool
  display_name: str
  brand_names: Optional[str] = None
  generic_names: Optional[str] = None
  manufacturer: Optional[str] = None
  product_type: Optional[str] = None
  purpose: Optional[str] = None
  indications: Optional[str] = None
  warnings: Optional[str] = None
  interactions_section: Optional[str] = None

class InteractionsRequest(BaseModel):
  drugs: List[str]

class InteractionsResponse(BaseModel):
  summary: str
  details: Optional[dict] = None

def _join(v):
  if isinstance(v, list):
    return ", ".join(v)
  return v or ""

def _first(v):
  if isinstance(v, list) and v:
    return str(v[0])
  if isinstance(v, str) and v.strip():
    return v
  return None

@app.get("/healthz")
async def healthz():
  return {"ok": True}

@app.post("/drug", response_model=DrugResponse)
async def get_drug(req: DrugRequest):
  q = req.name.strip()
  if not q:
    raise HTTPException(status_code=400, detail="Empty name")

  search = f'openfda.brand_name:"{q}"+OR+openfda.generic_name:"{q}"'
  params = {"search": search, "limit": 1}

  async with httpx.AsyncClient(timeout=20) as client:
    r = await client.get(OPEN_FDA_URL, params=params)
    if r.status_code == 404:
      return DrugResponse(found=False, display_name=q)
    r.raise_for_status()
    data = r.json()

  results = data.get("results", [])
  if not results:
    return DrugResponse(found=False, display_name=q)

  first = results[0]
  openfda = first.get("openfda", {})
  display = (_join(openfda.get("brand_name")) or "").split(",")[0] or \
            (_join(openfda.get("generic_name")) or "").split(",")[0] or q

  return DrugResponse(
    found=True,
    display_name=display,
    brand_names=_join(openfda.get("brand_name")),
    generic_names=_join(openfda.get("generic_name")),
    manufacturer=_join(openfda.get("manufacturer_name")),
    product_type=_join(openfda.get("product_type")),
    purpose=_first(first.get("purpose")),
    indications=_first(first.get("indications_and_usage")),
    warnings=_first(first.get("warnings")),
    interactions_section=_first(first.get("drug_interactions")),
  )

@app.post("/interactions", response_model=InteractionsResponse)
async def interactions(req: InteractionsRequest):
  # TODO:
  # 1) Resolve each drug to RxCUI (RxNorm) and call RxNav interactions API
  #    OR
  # 2) Pull openFDA label sections and feed them to a Google AI Studio model
  #    via LangChain to summarize potential interactions with citations.
  #
  # For now, we just echo the list.
  if not req.drugs:
    raise HTTPException(status_code=400, detail="No drugs supplied")

  summary = "Selected drugs:\n- " + "\n- ".join(req.drugs) + \
            "\n\n(Implement RxNav/AI-powered interaction logic here.)"
  return InteractionsResponse(summary=summary)
