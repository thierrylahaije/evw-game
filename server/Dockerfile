FROM python:3.13-slim
WORKDIR /app
COPY score_api.py /app/score_api.py
ENV EVW_API_HOST=0.0.0.0 EVW_API_PORT=8787
EXPOSE 8787
CMD ["python", "-u", "score_api.py"]
