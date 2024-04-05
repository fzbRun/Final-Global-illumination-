using System;
using Unity.VisualScripting;
using UnityEngine;
using UnityEngine.Rendering;
using static CameraSetting;
using static PipelineAsset;
using static UnityEditor.ShaderData;

public partial class CameraRenderer
{

    public const float renderScaleMin = 0.1f, renderScaleMax = 2.0f;

    static CameraSetting defaultCameraSetting = new CameraSetting();
    static bool copyTextureSupported = SystemInfo.copyTextureSupport > CopyTextureSupport.None;

    ScriptableRenderContext context;    //�൱��Opengl�е�֡����
    int pipelineMode;
    CullingResults cull;
    Camera camera;
    CommandBuffer buffer = new CommandBuffer()  //����棬��Ų�ͬ�������Ⱦ�����֡����submitʱ������buffer�е�������������Ӧ��������ݡ�
    {
        name = "Render Camera"
    };
    CommandBuffer RSMBuffer = new CommandBuffer { name = "RSM" };
    CommandBuffer pipelineBuffer;
    Lighting light = new Lighting();
    PostFXSetting postFXSetting = new PostFXSetting();
    PostFXStack postFXStack = new PostFXStack();
    bool allowHDR, useRenderScale;
    int colorLUTResolution;
    Material material;  //������������
    Shader deferredLightShader = Shader.Find("Custom RP/deferredLit");
    Material materialDeferredLight; //���������ӳ���Ⱦ����

    Global_illumination GI = new Global_illumination();
    float[] voxelBox;
    float testTime = 0.0f;
    int testNum = 0;

    static ShaderTagId
        unlitShaderTagID = new ShaderTagId("SRPDefaultUnlit"),
        litShaderTagID = new ShaderTagId("CustomLit");

    //static int frameBufferID = Shader.PropertyToID("_CameraFrameBuffer");   //��ɫ�����
    static int colorAttachmentID = Shader.PropertyToID("_CameraColorAttachment");   //��ɫ������
    static int depthAttachmentID = Shader.PropertyToID("_CameraDepthAttachment");   //��Ȼ�����
    static int colorTextureID = Shader.PropertyToID("_CameraColorTexture");
    static int depthTextureID = Shader.PropertyToID("_CameraDepthTexture");

    bool useColorTexture, useDepthTexture, useIntermediateBuffer;
    static int sourceTextureID = Shader.PropertyToID("_SourceTexture");
    static int srcBlendID = Shader.PropertyToID("_CameraSrcBlend");
	static int dstBlendID = Shader.PropertyToID("_CameraDstBlend");
    static int bufferSizeID = Shader.PropertyToID("_CameraBufferSize");

    //�ӳ���Ⱦ����
    static int albedoTextureID = Shader.PropertyToID("_AlbedoTexture");
    static int normalTextureID = Shader.PropertyToID("_NormalTexture");
    static int MVRMTextureID = Shader.PropertyToID("_MVRMTexture");    //MotionVector��rough��metallic
    static int EmissionAndOcclusionTextureID = Shader.PropertyToID("_EmissionAndOcclusionTexture");
    RenderTargetIdentifier[] gbufferID = new RenderTargetIdentifier[4];

    static int RSMTextureID = Shader.PropertyToID("_RSMTexture");
    static int RSMNormalTextureID = Shader.PropertyToID("_RSMNormalTexture");
    static int RSMDepthTextureID = Shader.PropertyToID("_RSMDepthTexture");
    RenderTargetIdentifier[] RSMID = new RenderTargetIdentifier[2];

    static string[] pipelineModeKeyWord =
    {
        "_FORWARDPIPELINE",
        "_DEFERREDPIPELINE"
    };

    Texture2D missingTexture;

    Vector2Int bufferSize;

    public CameraRenderer(Shader shader)
    {
        material = CoreUtils.CreateEngineMaterial(shader);
        materialDeferredLight = CoreUtils.CreateEngineMaterial(deferredLightShader);
        missingTexture = new Texture2D(1, 1)
        {
            hideFlags = HideFlags.HideAndDontSave,
            name = "Missing"
        };
        missingTexture.SetPixel(0, 0, Color.white * 0.5f);
        missingTexture.Apply(true, true);
    }

    public void Dispose()
    {
        CoreUtils.Destroy(material);
        CoreUtils.Destroy(materialDeferredLight);
        CoreUtils.Destroy(missingTexture);
        GI.CleanUpWithoutBuffer();
    }

    void Draw(RenderTargetIdentifier from, RenderTargetIdentifier to, bool useDepth)
    {
        buffer.SetGlobalTexture(sourceTextureID, from);
        buffer.SetRenderTarget(to, RenderBufferLoadAction.DontCare, RenderBufferStoreAction.Store);
        buffer.DrawProcedural(Matrix4x4.identity, material, useDepth ? 1 : 0, MeshTopology.Triangles, 3);
    }

    void DrawFinal(CameraSetting.FinalBlendMode finalBlendMode)
    {
        buffer.SetGlobalFloat(srcBlendID, (float)finalBlendMode.source);
        buffer.SetGlobalFloat(dstBlendID, (float)finalBlendMode.destination);
        buffer.SetGlobalTexture(sourceTextureID, colorAttachmentID);
        buffer.SetRenderTarget(BuiltinRenderTextureType.CameraTarget,
            finalBlendMode.destination == BlendMode.Zero ? RenderBufferLoadAction.DontCare : RenderBufferLoadAction.Load,
            RenderBufferStoreAction.Store);
        buffer.SetViewport(camera.pixelRect);   //SetRenderTargetz֮��Ὣ�ӿڱ任����Ļ��С��������Ҫ�޸�
        buffer.DrawProcedural(Matrix4x4.identity, material, 0, MeshTopology.Triangles, 3);
        buffer.SetGlobalFloat(srcBlendID, 1f);
        buffer.SetGlobalFloat(dstBlendID, 0f);
    }

    //��Ⱦǰ��׼��
    public void setUp()
    {

        //��Ⱦ��Ӱʱ���ὫVP����תΪ���տռ�ģ�������������������Խ�֮�����
        context.SetupCameraProperties(camera);
        CameraClearFlags flags = camera.clearFlags; //flags˳��Ϊ��պУ���ɫ����Ⱥ�nothing��ǰ��İ�������ģ�����Ϊ��պ�ʱ��Ҳ�������ɫ�����

        buffer.EnableShaderKeyword(pipelineModeKeyWord[pipelineMode]);
        buffer.DisableShaderKeyword(pipelineModeKeyWord[1 - pipelineMode]);

        //�Ƿ�ʹ���м�����
        useIntermediateBuffer = useColorTexture || useDepthTexture || postFXStack.isActive || useRenderScale;

        if((pipelineMode == 0 && useIntermediateBuffer) || pipelineMode == 1)
        {
            if (flags > CameraClearFlags.Color)
            {
                camera.clearFlags = CameraClearFlags.Color; //������
            }

            buffer.GetTemporaryRT(colorAttachmentID, bufferSize.x, bufferSize.y, 0, FilterMode.Bilinear,
                    allowHDR ? RenderTextureFormat.DefaultHDR : RenderTextureFormat.Default);
            buffer.GetTemporaryRT(depthAttachmentID, bufferSize.x, bufferSize.y, 32, FilterMode.Point, RenderTextureFormat.Depth);
            buffer.SetRenderTarget(colorAttachmentID, RenderBufferLoadAction.DontCare, RenderBufferStoreAction.Store,
                                    depthAttachmentID, RenderBufferLoadAction.DontCare, RenderBufferStoreAction.Store);
            //ÿ֡����Ҫ����
            //���뽫�����clear�����w����͸������Ϊ0��������պн����ᱻ����Ļ��渲��
            buffer.ClearRenderTarget(flags <= CameraClearFlags.Depth, flags == CameraClearFlags.Color, new Color(0, 0, 0, 0));
        }

        if (pipelineMode == 1)
        {

            buffer.GetTemporaryRT(albedoTextureID, bufferSize.x, bufferSize.y, 0, FilterMode.Bilinear, RenderTextureFormat.ARGB32);
            buffer.GetTemporaryRT(normalTextureID, bufferSize.x, bufferSize.y, 0, FilterMode.Point, RenderTextureFormat.ARGB2101010);
            buffer.GetTemporaryRT(MVRMTextureID, bufferSize.x, bufferSize.y, 0, FilterMode.Point, RenderTextureFormat.ARGB64);
            buffer.GetTemporaryRT(EmissionAndOcclusionTextureID, bufferSize.x, bufferSize.y, 0, FilterMode.Point,
                                   allowHDR ? RenderTextureFormat.DefaultHDR : RenderTextureFormat.Default);

            gbufferID[0] = albedoTextureID;
            gbufferID[1] = normalTextureID;
            gbufferID[2] = MVRMTextureID;
            gbufferID[3] = EmissionAndOcclusionTextureID;

            buffer.SetRenderTarget(gbufferID, depthAttachmentID);
            buffer.ClearRenderTarget(true, true, new Color(0, 0, 0, 0));

        }

        buffer.BeginSample(SampleName);
        buffer.SetGlobalTexture(colorTextureID, missingTexture);
        buffer.SetGlobalTexture(depthTextureID, missingTexture);
        ExecuteBuffer();

        sendParametersToShader();

    }

    void ExecuteBuffer()
    {
        context.ExecuteCommandBuffer(buffer);   //��buffer�е������õ�context��
        buffer.Clear();
    }

    void ExecuteBuffer(CommandBuffer executeBuffer)
    {
        context.ExecuteCommandBuffer(executeBuffer);
        executeBuffer.Clear();
    }

    void bufferBeginSample(CommandBuffer sampleBuffer)
    {
        sampleBuffer.BeginSample(sampleBuffer.name);
        ExecuteBuffer(sampleBuffer);
    }

    void bufferEndSample(CommandBuffer sampleBuffer)
    {
        sampleBuffer.EndSample(sampleBuffer.name);
        ExecuteBuffer(sampleBuffer);
    }

    void submit()
    {

        buffer.EndSample(SampleName);
        ExecuteBuffer();
        context.Submit();

    }

    void copyAttachment()
    {
        if (useColorTexture)
        {
            buffer.GetTemporaryRT(colorTextureID, bufferSize.x, bufferSize.y, 0, FilterMode.Bilinear, 
                allowHDR ? RenderTextureFormat.DefaultHDR : RenderTextureFormat.Default);
            if (copyTextureSupported)
            {
                buffer.CopyTexture(colorAttachmentID, colorTextureID);
            }
            else
            {
                Draw(colorAttachmentID, colorTextureID, false);
            }
        }

        if (useDepthTexture)
        {
            buffer.GetTemporaryRT(depthTextureID, bufferSize.x, bufferSize.y, 32, FilterMode.Point, RenderTextureFormat.Depth);
            if (copyTextureSupported)
            {
                buffer.CopyTexture(depthAttachmentID, depthTextureID);
            }
            else
            {
                Draw(depthAttachmentID, depthTextureID, true);
            }
        }

        if (!copyTextureSupported)
        {
            //���ڽ���ȾĿ����Ϊ����ʱ�������Ǵ���ģ�͸�������岻�ᱻ��Ⱦ�������������Ҫ��֮��Ϊ��ɫ���������
            buffer.SetRenderTarget(colorAttachmentID, RenderBufferLoadAction.DontCare, RenderBufferStoreAction.Store,
                                    depthAttachmentID, RenderBufferLoadAction.DontCare, RenderBufferStoreAction.Store);
        }

        ExecuteBuffer();
    }

    void cleanUp()
    {
        light.CleanUp();
        //GI.CleanUp();
        if (useIntermediateBuffer)
        {
            buffer.ReleaseTemporaryRT(colorAttachmentID);
            buffer.ReleaseTemporaryRT(depthAttachmentID);
            if (useColorTexture)
            {
                buffer.ReleaseTemporaryRT(colorTextureID);
            }
            if (useDepthTexture)
            {
                buffer.ReleaseTemporaryRT(depthTextureID);
            }
        }
        if (pipelineMode == 1)
        {
            buffer.ReleaseTemporaryRT(albedoTextureID);
            buffer.ReleaseTemporaryRT(normalTextureID);
            buffer.ReleaseTemporaryRT(MVRMTextureID);
            buffer.ReleaseTemporaryRT(EmissionAndOcclusionTextureID);
            if (GI.giSetting.RSM.useRSM)
            {
                buffer.ReleaseTemporaryRT(RSMTextureID);
                buffer.ReleaseTemporaryRT(RSMNormalTextureID);
                buffer.ReleaseTemporaryRT(RSMDepthTextureID);
            }
        }
    }

    //cleanUp����Ҫʹ��buffer���ͷ��ڴ棬������Щ��ֻԤ�ȴ�����ָ������У�����ֱ��ʹ�ã��Ǵ���submit��һ��ִ��
    //���Զ���һЩ������buffer�����������ֱ�buffer���������õ���Դ����������buffer��������ʱ��������buffer��ΪtargetTexture��
    //��ô�ͱ�����submit�����ͷţ���Ϊ֮ǰ�ͷŲ��ˣ���buffer�����ţ�
    void cleanUpWithoutBuffer()
    {
        GI.CleanUpWithoutBuffer();
    }

    bool Cull(float maxDistance)
    {
        //�������޳�����
        if(camera.TryGetCullingParameters(out ScriptableCullingParameters p))
        {

            p.shadowDistance = Mathf.Min(maxDistance, camera.farClipPlane);
            cull = context.Cull(ref p);
            return true;

        }

        return false;

    }

    void sendParametersToShader()
    {
        Shader.SetGlobalFloat("_Time", Time.time % 1000);
    }

    void makeGlobalIllumination(CullingResults cull, PipelineSystem pipelineSystem)
    {

        if (pipelineMode == 1)
        {
            if (GI.giSetting.OnlyGI)
            {
                buffer.EnableShaderKeyword("_OnlyGI");
            }
            else
            {
                buffer.DisableShaderKeyword("_OnlyGI");
            }
            GI.makeIBL();

            if (GI.makeRSM(cull))
            {

                PerObjectData lightPerObjectFlags = pipelineSystem.useLightPerObject ? PerObjectData.LightData | PerObjectData.LightIndices : PerObjectData.None;

                var sortingSettings = new SortingSettings(camera)
                {
                    criteria = SortingCriteria.CommonOpaque
                };
                var drawingSettings = new DrawingSettings(unlitShaderTagID, sortingSettings)
                {

                    enableDynamicBatching = pipelineSystem.useDynamicBatching,
                    enableInstancing = pipelineSystem.useGPUInstancing,
                    perObjectData = PerObjectData.Lightmaps | PerObjectData.ShadowMask | PerObjectData.LightProbe | PerObjectData.OcclusionProbe | PerObjectData.LightProbeProxyVolume |
                        PerObjectData.OcclusionProbeProxyVolume | PerObjectData.ReflectionProbes | lightPerObjectFlags

                };

                drawingSettings.SetShaderPassName(1, new ShaderTagId("RSMPass"));
                var filteringSettings = new FilteringSettings(RenderQueueRange.opaque); //RSM�Ͳ����ǹ�Դ�����ˣ�Ҫ��ԭ���Ĵ���̫�鷳��

                bufferBeginSample(RSMBuffer);

                RSMBuffer.GetTemporaryRT(RSMTextureID, GI.giSetting.RSM.mapSize, GI.giSetting.RSM.mapSize, 0, FilterMode.Bilinear, RenderTextureFormat.BGRA32);
                RSMBuffer.GetTemporaryRT(RSMNormalTextureID, GI.giSetting.RSM.mapSize, GI.giSetting.RSM.mapSize, 0, FilterMode.Bilinear, RenderTextureFormat.BGRA32);
                RSMBuffer.GetTemporaryRT(RSMDepthTextureID, GI.giSetting.RSM.mapSize, GI.giSetting.RSM.mapSize, 32, FilterMode.Point, RenderTextureFormat.Depth);
                RSMID[0] = RSMTextureID;
                RSMID[1] = RSMNormalTextureID;

                RSMBuffer.SetRenderTarget(RSMID, RSMDepthTextureID);
                RSMBuffer.ClearRenderTarget(true, true, new Color(0, 0, 0, 0));
                ExecuteBuffer(RSMBuffer);
                context.DrawRenderers(cull, ref drawingSettings, ref filteringSettings);

                buffer.SetViewProjectionMatrices(camera.worldToCameraMatrix, camera.projectionMatrix);
                bufferEndSample(RSMBuffer);

            }
            else
            {
                //ǰ����Ⱦ������ʱ���ٸ�
            }

            GI.makeLPV(bufferSize);

            buffer.SetRenderTarget(gbufferID, depthAttachmentID);
            ExecuteBuffer();

        }
        /*
        testNum++;
        testTime += Time.deltaTime;
        if(testTime >= 30.0f)
        {
            Debug.Log(testNum / 30);
            testNum = 0;
            testTime = 0.0f;
        }
        */
    }

    public void setDefferPipelineShaderParam()
    {
        //camera.worldToCamera�Լ�shader�е�unity_worldToCamera����Unity_Matrix_V����ͬ����֪��Ϊʲô
        Matrix4x4 ViewMatrix = URPMath.makeViewMatrix4x4(camera);
        Matrix4x4 ProjectionMatrix = camera.projectionMatrix;//URPMath.makeProjectionMatrix4x4(camera);   //��ʵ��camera.projectionMatrix��һ����
        //һ��Ҫ����һ��������͸��ͶӰ������shader�еĲ�һ�����޿�!!!
        ProjectionMatrix = GL.GetGPUProjectionMatrix(ProjectionMatrix, true);
        Shader.SetGlobalMatrix("ViewProjectionMatrix", ProjectionMatrix * ViewMatrix);
        Shader.SetGlobalMatrix("ViewMatrix", ViewMatrix);
        Shader.SetGlobalMatrix("ProjectionMatrix", ProjectionMatrix);
        Shader.SetGlobalMatrix("inverseViewProjectionMatrix", (ProjectionMatrix * ViewMatrix).inverse);
        Shader.SetGlobalMatrix("inverseProjectionMatrix", ProjectionMatrix.inverse);
        Shader.SetGlobalMatrix("inverseViewMatrix", ViewMatrix.inverse);
    }

    void deferredPipelineLightRendering()
    {

        //�ӳٹ���
        buffer.SetRenderTarget(colorAttachmentID, RenderBufferLoadAction.DontCare, RenderBufferStoreAction.Store,
                               depthAttachmentID, RenderBufferLoadAction.DontCare, RenderBufferStoreAction.Store);
        buffer.DrawProcedural(Matrix4x4.identity, materialDeferredLight, 0, MeshTopology.Triangles, 3);

        if (useColorTexture)
        {
            buffer.GetTemporaryRT(colorTextureID, bufferSize.x, bufferSize.y, 0, FilterMode.Bilinear,
                allowHDR ? RenderTextureFormat.DefaultHDR : RenderTextureFormat.Default);
            if (copyTextureSupported)
            {
                buffer.CopyTexture(colorAttachmentID, colorTextureID);
            }
            else
            {
                Draw(colorAttachmentID, colorTextureID, false);
            }
        }

        if (!copyTextureSupported)
        {
            buffer.SetRenderTarget(colorAttachmentID, RenderBufferLoadAction.DontCare, RenderBufferStoreAction.Store,
                                    depthAttachmentID, RenderBufferLoadAction.DontCare, RenderBufferStoreAction.Store);
        }

        ExecuteBuffer();

    }

    void DrawVisibleGeometry(PipelineSystem pipelineSystem, int renderinLayerMask)
    {

        string pipelineName = pipelineMode == 0 ? "Forward Pipeline" : "Deffered Pipeline";
        pipelineBuffer = new CommandBuffer { name = pipelineName };
        bufferBeginSample(pipelineBuffer);

        PerObjectData lightPerObjectFlags = pipelineSystem.useLightPerObject ? PerObjectData.LightData | PerObjectData.LightIndices : PerObjectData.None;

        var sortingSettings = new SortingSettings(camera)
        {
            criteria = SortingCriteria.CommonOpaque
        };
        var drawingSettings = new DrawingSettings(unlitShaderTagID, sortingSettings)
        {

            enableDynamicBatching = pipelineSystem.useDynamicBatching,
            enableInstancing = pipelineSystem.useGPUInstancing,
            perObjectData = PerObjectData.Lightmaps | PerObjectData.ShadowMask | PerObjectData.LightProbe | PerObjectData.OcclusionProbe | PerObjectData.LightProbeProxyVolume |
                PerObjectData.OcclusionProbeProxyVolume | PerObjectData.ReflectionProbes | lightPerObjectFlags

        };

        drawingSettings.SetShaderPassName(1, litShaderTagID);
        var filteringSettings = new FilteringSettings(RenderQueueRange.opaque, renderingLayerMask: (uint)renderinLayerMask);
        context.DrawRenderers(cull, ref drawingSettings, ref filteringSettings);

        //makeGlobalIllumination(cull, pipelineSystem);

        if (pipelineMode == 0)
        {
            context.DrawSkybox(camera);
            if (useColorTexture || useDepthTexture)
            {
                copyAttachment();
            }
        }
        else
        {

            buffer.GetTemporaryRT(depthTextureID, bufferSize.x, bufferSize.y, 32, FilterMode.Point, RenderTextureFormat.Depth);
            if (copyTextureSupported)
            {
                buffer.CopyTexture(depthAttachmentID, depthTextureID);
            }
            else
            {
                Draw(depthAttachmentID, depthTextureID, true);
            }
            ExecuteBuffer();

            setDefferPipelineShaderParam();
            //�Ȳ�����ǰ����Ⱦ��ȫ�ֹ���
            makeGlobalIllumination(cull, pipelineSystem);
            deferredPipelineLightRendering();
            context.DrawSkybox(camera);

        }

        sortingSettings.criteria = SortingCriteria.CommonTransparent;
        drawingSettings.sortingSettings = sortingSettings;
        filteringSettings.renderQueueRange = RenderQueueRange.transparent;
        context.DrawRenderers(cull, ref drawingSettings, ref filteringSettings);

        bufferEndSample(pipelineBuffer);

    }

    public Vector3 calcCenters(Camera camera, ShadowSetting shadowSetting)
    {
        float num = shadowSetting.directional.cascadeCount;
        float k = 0.5f;
        float n = camera.nearClipPlane;
        //float f = camera.farClipPlane;
        float f = Mathf.Min(shadowSetting.maxDistance, camera.farClipPlane);
        Vector3 centers;
        centers.x = k * n * Mathf.Pow(f / n, 1 / num) + (1.0f - k) * (n + (f - n) * (1 / num));
        if(num <= 2)
        {
            centers.y = 0;
        }
        else
        {
            centers.y = k * n * Mathf.Pow(f / n, 2 / num) + (1.0f - k) * (n + (f - n) * (2 / num));
        }
        if(num <= 3)
        {
            centers.z = 0;
        }
        else
        {
            centers.z = k * n * Mathf.Pow(f / n, 3 / num) + (1.0f - k) * (n + (f - n) * (3 / num));
        }
        
        return centers / f;
        //return new Vector3(0.3f, 0.4f, 0.5f);
    }

    public void changeCenters(Camera camera, ref ShadowSetting shadowSetting)
    {
        Vector3 centers = calcCenters(camera, shadowSetting);
        shadowSetting.directional.cascadeRatio1 = centers.x;
        shadowSetting.directional.cascadeRatio2 = centers.y;
        shadowSetting.directional.cascadeRatio3 = centers.z;
    }

    public void Render(ScriptableRenderContext context, Camera camera, PipelineSystem pipelineSystem,
        ShadowSetting shadowSetting, PostFXSetting postFXSetting, 
        CameraBufferSetting cameraBuffer, GISetting giSetting, int colorLUTResolution)
    {

        this.context = context;
        this.camera = camera;
        this.pipelineMode = (int)pipelineSystem.pipelineMode;
        this.GI.SetUp(context, giSetting, camera, buffer);

        var crpCamera = camera.GetComponent<CustomRenderPipelineCamera>();
        CameraSetting cameraSetting = crpCamera ? crpCamera.Settings : defaultCameraSetting;

        if(camera.cameraType == CameraType.Reflection)
        {
            useColorTexture = cameraBuffer.copyColorReflection;
            useDepthTexture = cameraBuffer.copyDepthReflection;
        }
        else
        {
            useColorTexture = cameraBuffer.copyColor && cameraSetting.copyColor;
            useDepthTexture = cameraBuffer.copyDepth && cameraSetting.copyDepth;
        }

        float renderScale = cameraBuffer.renderScale;
        renderScale = cameraSetting.getRenderScale(renderScale);
        useRenderScale = renderScale < 0.99f || renderScale > 1.01f;

        PrepareBuffer();
        PrepareForSceneWindow();

        if (!Cull(shadowSetting.maxDistance))   //��׶���޳�
        {
            return;
        }
        
        this.allowHDR = cameraBuffer.allowHDR && camera.allowHDR;

        if (useRenderScale)
        {
            renderScale = Mathf.Clamp(renderScale, renderScaleMin, renderScaleMax);
            bufferSize.x = (int)(camera.pixelWidth * renderScale);
            bufferSize.y = (int)(camera.pixelHeight * renderScale);
        }
        else
        {
            bufferSize.x = camera.pixelWidth;
            bufferSize.y = camera.pixelHeight;
        }

        cameraBuffer.fxaa.enabled &= cameraSetting.allowFXAA;

        this.colorLUTResolution = colorLUTResolution;

        buffer.BeginSample(SampleName);

        buffer.SetGlobalVector(bufferSizeID, new Vector4(
            1.0f / bufferSize.x, 1.0f / bufferSize.y,
            bufferSize.x, bufferSize.y));

        ExecuteBuffer();
        changeCenters(camera, ref shadowSetting);   //�õ�����
        light.setUp(context, cull, shadowSetting, pipelineSystem.useLightPerObject,
            cameraSetting.maskLights ? cameraSetting.renderingLayerMask : -1);   //���������ݴ���GPU��������Ⱦ��Ӱ
        if (cameraSetting.overridePostFX)
        {
            postFXStack.setUp(context, camera, cameraSetting.postFXSetting, allowHDR, colorLUTResolution, 
                cameraSetting.finalBlendMode, bufferSize, cameraBuffer.bicubicRescaling, cameraBuffer.fxaa, cameraSetting.keepAlpha);  //���ú��ڴ���
        }
        else
        {
            postFXStack.setUp(context, camera, postFXSetting, allowHDR, colorLUTResolution, 
                cameraSetting.finalBlendMode, bufferSize, cameraBuffer.bicubicRescaling, cameraBuffer.fxaa, cameraSetting.keepAlpha);  //���ú��ڴ���
        }
        buffer.EndSample(SampleName);
        setUp();    //�жϺ��ڴ������������

        DrawVisibleGeometry(pipelineSystem, cameraSetting.renderingLayerMask);
        DrawUnSupportedShaders();

        DrawGizmosBeforeFX();   //Gizmos����Ļ����Ⱦ������ʱ��Ļ��û�л��棬����������Gizmos���ᱻ�ڵ��������渳����Ҳ�����赲Gizoms����֪��Ϊɶ����������ǰ�档
        if (postFXStack.isActive)
        {
            postFXStack.Render(colorAttachmentID);
        }
        else if(useIntermediateBuffer)
        {
            //��������Ⱦ����ʱ�������޸�����������Ĵ�С���������ߴ�С��ͬ������ʹ��buffer.CopyTexture����
            if (camera.targetTexture && bufferSize == camera.targetTexture.texelSize)
            {
                buffer.CopyTexture(colorAttachmentID, camera.targetTexture);
            }
            else
            {
                //Draw(colorAttachmentID, BuiltinRenderTextureType.CameraTarget, false);
                DrawFinal(cameraSetting.finalBlendMode);    //�����Ҫ�ӿڱ任����Ȼ��ʵ���˲������ӿڱ任����Ҳû��
            }
            ExecuteBuffer();
        }
        DrawGizmosAfterFX();

        cleanUp();

        submit();

        //cleanUpWithoutBuffer();
    }

}