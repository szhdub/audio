#HTTP Server stuff
from http.server import BaseHTTPRequestHandler, HTTPServer, SimpleHTTPRequestHandler
import json
import base64
from io import BytesIO
import math

#ML stuff
import torch
import os, glob, random

gpu_model = None
gpu_pipe = {}


import whisper
import os
import numpy as np
import torch

DEVICE = "cuda" if torch.cuda.is_available() else "cpu"

model_base = whisper.load_model("base", device=DEVICE)
#model_med = whisper.load_model("medium", device=DEVICE)
print(
    f"Model is {'multilingual' if model_base.is_multilingual else 'English-only'} "
    f"and has {sum(np.prod(p.shape) for p in model_base.parameters()):,} parameters."
)

import tempfile
import time

class RequestHandler(BaseHTTPRequestHandler):
    def end_headers (self):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header("Access-Control-Allow-Methods", "GET, POST, HEAD, PUT, DELETE")
        self.send_header("Access-Control-Allow-Headers", "Cache-Control, Pragma, Origin, Authorization, Location, Content-Type, X-Requested-With, Extra")
        self.send_header("Access-Control-Max-Age", "36000")
        
        SimpleHTTPRequestHandler.end_headers(self)

    def reply(self, message):
        isJson = False
        if (type(message) is dict) or (type(message) is list):
            isJson = True
            message = json.dumps(message)
        self.protocol_version = "HTTP/1.1"
        self.send_response(200)
        self.send_header("Content-Length", len(message))
        if isJson:
            self.send_header("Content-Type", "application/json")
        self.end_headers()
        if (type(message) is bytes):
            self.wfile.write(message)
        else:
            self.wfile.write(bytes(message, "utf8"))

    def do_GET(self):
        self.reply("Hello!")

    def do_OPTIONS(self):
        self.reply("Hello!")

    def do_POST(self):
        length = self.headers['content-length']
        data = self.rfile.read(int(length))
        obj = json.loads(data)
        #print(obj)
        self.whisper(base64.b64decode(obj['message']), obj['language'] or "en", obj['quality'] or "base")

    def whisper(self, obj, lang, qual):
        with tempfile.NamedTemporaryFile(suffix=".wav") as f:
            f.write(obj)
            f.flush()
            start = time.time()
            model = model_med if qual == "medium" else model_base
            result = model.transcribe(
                f.name,
                language=lang,
                task=None,
                fp16=torch.cuda.is_available(),
                #**transcribe_options
            )
            end = time.time()
            print(result)
            self.reply({"result": result['text'], "took": end-start, "lang": lang, "qual": qual})

def run():
    if torch.cuda.device_count() == 0:
        print("no cuda device")
    #    return
    httpd = HTTPServer(('', 8080), RequestHandler)
    httpd.timeout = 60*60
    while True: httpd.handle_request()

run()

