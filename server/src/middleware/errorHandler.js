import { log } from '../utils/logger.js';

export class HttpError extends Error {
  constructor(status, code, message) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

export function errorHandler(err, _req, res, _next) {
  const status = err.status || 500;
  if (status >= 500) log.error(err.message, err.stack);
  res.status(status).json({
    error: err.code || 'internal_error',
    message: status >= 500 ? 'internal server error' : err.message,
  });
}
