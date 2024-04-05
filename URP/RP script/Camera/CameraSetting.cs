using System;
using UnityEngine;
using UnityEngine.Rendering;

[Serializable]
public class CameraSetting
{

	public bool copyColor = true, copyDepth = true;

	[RenderingLayerMaskField]
	public int renderingLayerMask = -1;

	public bool maskLights = false;

	public enum RenderScaleMode
    {
		Inherit, Multiply, Override
    }

	[SerializeField]
	RenderScaleMode renderScaleMode = RenderScaleMode.Inherit;

	[Range(0.1f, 2.0f)]
	public float renderScale = 1.0f;

	public float getRenderScale(float scale)
	{
		//���ʱinferit�ͱ���ԭ������Ⱦ���ߵ��������ӣ����ʱmultiply�ͽ�������ˣ����ʱoverride�����������������
		return renderScaleMode == RenderScaleMode.Inherit ? scale :
			renderScaleMode == RenderScaleMode.Override ? renderScale : scale * renderScale;

	}


	public bool overridePostFX = false;
	public PostFXSetting postFXSetting = default;
	public bool allowFXAA = false;
	public bool keepAlpha = false;

	[Serializable]
	public struct FinalBlendMode
	{
		public BlendMode source, destination;
	}

	public FinalBlendMode finalBlendMode = new FinalBlendMode
	{
		source = BlendMode.One,
		destination = BlendMode.Zero
	};
}
