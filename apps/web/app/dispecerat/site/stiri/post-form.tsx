import { ActionForm } from '../../_components/action-form';
import { savePost } from './actions';

export type PostFields = { id?: string; title?: string; excerpt?: string | null; body?: string; cover_url?: string | null; published?: boolean };
type Labels = Record<'headline' | 'excerpt' | 'body' | 'cover' | 'publishNow' | 'save' | 'saving' | 'formatHelp', string>;

export function PostForm({ post, labels }: { post?: PostFields; labels: Labels }) {
  return (
    <ActionForm action={savePost} submitLabel={labels.save} pendingLabel={labels.saving}>
      {post?.id && <input type="hidden" name="id" value={post.id} />}
      <fieldset>
        <label>{labels.headline}<input name="title" required minLength={3} maxLength={160} defaultValue={post?.title ?? ''} /></label>
        <label>{labels.excerpt}<input name="excerpt" maxLength={400} defaultValue={post?.excerpt ?? ''} /></label>
        <label>
          {labels.body}
          <textarea name="body" rows={12} maxLength={40000} defaultValue={post?.body ?? ''} />
          <span className="meta" style={{ fontWeight: 400 }}>{labels.formatHelp}</span>
        </label>
        {post?.cover_url && <img src={post.cover_url} alt="" className="thumb" />}
        <label>{labels.cover}<input name="cover" type="file" accept="image/jpeg,image/png,image/webp" /></label>
        {!post?.published && (
          <label className="check"><input type="checkbox" name="publish_now" />{labels.publishNow}</label>
        )}
      </fieldset>
    </ActionForm>
  );
}
