from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from jose import JWTError
from app.core.security import decode_access_token

router = APIRouter()


@router.websocket("/ws/emergencies/{emergency_id}")
async def emergency_socket(websocket: WebSocket, emergency_id: str, token: str):
    try:
        decode_access_token(token)
    except JWTError:
        await websocket.close(code=1008)
        return

    await websocket.accept()

    try:
        while True:
            message = await websocket.receive_json()
            # In the next realtime phase this becomes Redis pub/sub fan-out.
            await websocket.send_json({
                "type": "ack",
                "emergency_id": emergency_id,
                "data": message,
            })
    except WebSocketDisconnect:
        return
