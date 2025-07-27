from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.trustedhost import TrustedHostMiddleware
import uvicorn
from db import insert_message
import traceback

app = FastAPI()

# Trust proxy headers - IMPORTANT for Traefik
app.add_middleware(
    TrustedHostMiddleware, 
    # allowed_hosts=["localhost", "backend.localhost", "frontend.localhost", "traefik.localhost", "*.localhost"]
    allowed_hosts=["localhost", "*.localhost", "frontend.localhost",  "backend.localhost", "traefik.localhost"]
)

# CORS middleware (NEVER use wildcards for allow_origins)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["https://frontend.localhost:8443",
                   "https://backend.localhost:8443",
                   "https://traefik.localhost:8443"
                   ],
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    allow_headers=["*"],
)


@app.get("/")
def read_root():
    return {"Hello": "World"}

@app.post("/submit")
async def handle_submit(request: Request):
    data = await request.json()
    msg = data.get("message", "")
    print("Received:", msg)

     # debugging: check access the real client info through proxy headers
    client_ip = request.headers.get("X-Forwarded-For", request.client.host)
    original_scheme = request.headers.get("X-Forwarded-Proto", "http")
    original_host = request.headers.get("X-Forwarded-Host", request.headers.get("host"))
    print(f"Real client IP: {client_ip}")
    print(f"Original scheme: {original_scheme}")
    print(f"Original host: {original_host}")

    # db insert
    try:
        insert_message(msg)
        print("✅ Inserted into DB")
        return {"status": "saved"}
    except Exception as e:
        print("❌ DB Error:", str(e))
        traceback.print_exc()
        return {"status": "error", "detail": str(e)}


if __name__ == "__main__":
    uvicorn.run(app,
                host="0.0.0.0", 
                port=8001,
                proxy_headers=True,  # Essential for Traefik integration
                forwarded_allow_ips="*"  # Allow proxy headers from any IP (adjust for production)
                )