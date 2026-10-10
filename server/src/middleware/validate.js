import { HttpError } from './errorHandler.js';

export function validate(schema, source = 'body') {
  return (req, _res, next) => {
    const r = schema.safeParse(req[source]);
    if (!r.success) {
      const issue = r.error.issues[0];
      return next(new HttpError(400, 'validation_error', `${issue.path.join('.')}: ${issue.message}`));
    }
    req[source] = r.data;
    next();
  };
}
